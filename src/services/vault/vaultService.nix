# NixOS module applied to every machine selected by the vault service.
# Configures the Vault server (TLS, Raft storage, clustering, firewall, /etc/hosts).
#
# Cluster-level options (certificates, logLevel, enableUi, …) are defined in
# vaultClusterModule.nix and accessed here through:
#   config.clusterConfig.clusters.this.services.vault.*
#
# Per-machine information (name, fqdn, ips, serviceAddresses) is accessed through:
#   config.clusterConfig.clusters.this.machines.this
#
# The full list of vault peers comes from:
#   config.clusterConfig.clusters.this.services.vault.selectors

{
  config,
  lib,
  pkgs,
  ...
}:

let

  head = builtins.head;
  tail = builtins.tail;
  lists = lib.lists;
  flatten = lists.flatten;
  remove = lists.remove;
  forEach = lists.forEach;

  # Cluster-level vault service config
  vaultServiceCfg = config.clusterConfig.clusters.this.services.vault;
  # All machines that are selected for the vault service
  selectors = vaultServiceCfg.selectors;
  # The current machine
  thisMachine = config.clusterConfig.clusters.this.machines.this;
  # The cluster FQDN
  clusterFqdn = config.clusterConfig.clusters.this.fqdn;

  # helper functions

  # Get a list of IPs excluding DHCP configurations
  parseRealIps =
    ips:
    let
      ipList = flatten (lib.attrsets.mapAttrsToList (_name: value: value) ips);
    in
    remove "dhcp" ipList;

  get = {

    # Find serviceAddresses entries matching a given role for a host
    serviceAddresses =
      searchRole: host:
      (
        if host ? serviceAddresses then
          builtins.filter (elem: elem.role == searchRole) host.serviceAddresses
        else
          [ ]
      );

    # Get the listener addresses for a host. Falls back to the cluster-level defaults.
    listeners =
      host:
      let
        listeners = get.serviceAddresses "vault-listener" host;
      in
      if listeners == [ ] then
        [
          {
            address = vaultServiceCfg.listenerAddress;
            port = vaultServiceCfg.listenerPort;
          }
        ]
      else
        listeners;

    # All vault peers except the current machine
    otherServers = builtins.filter (server: server.fqdn != thisMachine.fqdn) selectors;

    # Resolve IP addresses for a host's listeners
    serverIps =
      host:
      let
        server = head (builtins.filter (selected: selected.fqdn == host.fqdn) selectors);
        isInt = input: (builtins.tryEval (lib.toInt input)).success;
        isV4Octet = input: if (isInt input) then ((lib.toInt input) <= 255) else false;
        isIpV4 = listener: builtins.all isV4Octet (lib.splitString "." listener.address);
        isAllInterfaces = listener: listener.address == "0.0.0.0";
      in
      remove "del" (
        flatten (
          forEach (get.listeners server) (
            listener:
            if isAllInterfaces listener then
              parseRealIps server.ips
            else if isIpV4 listener then
              listener.address
            else
              "del"
          )
        )
      );

    # Build the vault-specific FQDN for a host (e.g. node1.vault.example.com)
    hostFqdn = host: "${host.name}.vault.${clusterFqdn}";

    # Build the list of endpoint URLs for a host
    hostEndpoints =
      host: forEach (get.listeners host) (listener: "${get.hostFqdn host}:${toString listener.port}");

    # Build /etc/hosts entries for all vault peers
    hostsEntries = flatten (
      forEach selectors (
        host: forEach (get.serverIps host) (ip: "${ip} ${host.name} ${get.hostFqdn host}")
      )
    );

  };

  # Certificate settings from the cluster-level config, with resolved defaults
  certs = vaultServiceCfg.certificates;
  certOrg = certs.organization;

  basePath = certs.path.serverBase;
  caRootCertName =
    if certs.path.caRootCertName != "" then certs.path.caRootCertName else "${certOrg}-root";
  vaultCertName =
    if certs.path.vaultCertName != "" then certs.path.vaultCertName else "${certOrg}-vault";
  vaultKeyName =
    if certs.path.vaultKeyName != "" then certs.path.vaultKeyName else "${certOrg}-vault";

  rootCaFile = basePath + caRootCertName + ".crt";
  tlsCert = basePath + vaultCertName + ".crt";
  tlsKey = basePath + vaultKeyName + ".key";

  # Listener configuration for the current machine
  listeners = get.listeners thisMachine;
  defaultListener = head listeners;
  defaultListenerAddress = "${get.hostFqdn thisMachine}:${toString defaultListener.port}";
  clusterPort = defaultListener.port + 1;
  remainingListeners = tail listeners;

  firewallPorts = (forEach listeners (listener: listener.port)) ++ [ clusterPort ];

  clusterNameOpt = "vault.${clusterFqdn}";

in

{
  imports = [
    # Initialization modules for first-time Vault setup
    ./initialization/initScript.nix
  ];

  config = {

    networking.firewall.allowedTCPPorts = firewallPorts;
    networking.extraHosts = (builtins.concatStringsSep "\n" get.hostsEntries);

    environment.systemPackages = with pkgs; [
      vault-bin
      certstrap
      openssl
    ];

    services.vault = {
      enable = true;
      package = pkgs.vault-bin;

      # Primary listener
      address = defaultListenerAddress;
      tlsCertFile = tlsCert;
      tlsKeyFile = tlsKey;
      listenerExtraConfig = ''
        tls_client_ca_file = "${rootCaFile}"
        redact_addresses = "true"
      '';

      # Cluster settings
      extraConfig =
        let
          # If more than one listener is configured, add them
          remainingListenersConfig = forEach remainingListeners (listener: ''
            listener "tcp"{
              address = "${get.hostFqdn thisMachine}:${toString listener.port}"
              tls_cert_file = "${tlsCert}"
              tls_key_file = "${tlsKey}"
              tls_client_ca_file = "${rootCaFile}"
            }
          '');
        in
        ''
          ui = "${if vaultServiceCfg.enableUi then "true" else "false"}"
          disable_mlock = "true"
          api_addr = "https://${defaultListenerAddress}"
          cluster_addr = "https://${get.hostFqdn thisMachine}:${toString clusterPort}"
          cluster_name  = "${clusterNameOpt}"
          introspection_endpoint = "false"
          log_level = "${vaultServiceCfg.logLevel}"

          ${builtins.concatStringsSep "\n\n" remainingListenersConfig}
        '';

      ##########################
      # Storage — Raft
      ##########################

      # Reference architecture: https://developer.hashicorp.com/vault/tutorials/raft/raft-reference-architecture
      storageBackend = "raft";

      storageConfig =
        let
          # Build retry_join stanzas for every other vault server
          # https://developer.hashicorp.com/vault/docs/configuration/storage/raft#retry_join
          joinStanzas = flatten (
            forEach (get.otherServers) (
              vaultServer:
              forEach (get.listeners vaultServer) (listener: ''
                retry_join {
                  leader_api_addr = "https://${get.hostFqdn vaultServer}:${toString listener.port}"
                  leader_ca_cert_file = "${rootCaFile}"
                  leader_client_cert_file = "${tlsCert}"
                  leader_client_key_file = "${tlsKey}"
                }
              '')
            )
          );
        in
        ''
          node_id = "${config.networking.hostName}"
          ${(builtins.concatStringsSep "\n" joinStanzas)}
        '';

      # TODO: default_lease_ttl https://developer.hashicorp.com/vault/docs/configuration#default_lease_ttl
      # TODO: max_lease_ttl https://developer.hashicorp.com/vault/docs/configuration#max_lease_ttl
      # TODO: request_limiter https://developer.hashicorp.com/vault/docs/configuration#request_limiter
      # TODO: user lockout? https://developer.hashicorp.com/vault/docs/configuration#user_lockout
    };
  };

}
