{
  clusterInfo,
  selectors,
  roles,
  this,
}:
{
  config,
  lib,
  pkgs,
  ...
}:

let

  #imports 

  head = builtins.head;
  tail = builtins.tail;
  lists = lib.lists;
  flatten = lists.flatten;
  remove = lists.remove;
  forEach = lists.forEach;

  str = lib.types.str;
  listOf = lib.types.listOf;
  enum = lib.types.enum;

  mkOption = lib.mkOption;
  mkEnableOption = lib.mkEnableOption;

  # helper functions

  # get a list of ips excluding dhcp cobfigurations
  parseRealIps =
    ips:
    let
      ipList = flatten (lib.attrsets.mapAttrsToList (name: value: value) ips);
    in
    remove "dhcp" ipList;

  get = {

    serviceAddresses =
      searchRole: host:
      (
        if host ? serviceAddresses then
          builtins.filter (elem: elem.role == searchRole) host.serviceAddresses
        else
          [ ]
      );

    listeners =
      host:
      let
        listeners = get.serviceAddresses "vault-listener" host;
      in
      if listeners == [ ] then
        [
          {
            address = "0.0.0.0";
            port = 8200;
          }
        ]
      else
        listeners;

    otherServers = builtins.filter (server: server.fqdn != this.fqdn) selectors;

    serverIps =
      host:
      let
        server = head (builtins.filter (selected: selected.fqdn == host.fqdn) selectors); # selectors[host]
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

    hostFqdn = host: "${host.machineName}.vault.${clusterInfo.fqdn}";

    hostEndpoints =
      host: forEach (get.listeners host) (listener: "${get.hostFqdn host}:${toString listener.port}");

    hostsEntries = flatten (
      lists.forEach selectors (
        host: lists.forEach (get.serverIps host) (ip: "${ip} ${host.machineName} ${get.hostFqdn host}")
      )
    );

  };

in

{
  imports = [
    # root module for the initialization modules for firrst time vault configuration
    ./initialization/initScript.nix
  ];

  ##########################################################
  # Additional options for cluster configuration.
  # Other options are defined in the nixos service module for vault.

  options.services.vault.cluster = {

    enableUi = mkEnableOption "https://developer.hashicorp.com/vault/docs/configuration#ui";

    clusterName = mkOption {
      type = str;
      default = "vault." + clusterInfo.fqdn;
      description = "https://developer.hashicorp.com/vault/docs/configuration#cluster_name";
    };

    apiEndpoints = mkOption {
      type = listOf str;
      default = lists.flatten (forEach selectors (host: get.hostEndpoints host));
      description = ''
        List of url+port combination where a vault listener is configured. Depending on your configuration, not
        all enpoints are reachable.
      '';
    };

    logLevel = mkOption {
      type = enum [
        "trace"
        "debug"
        "info"
        "warn"
        "error"
      ];
      default = "info";
      description = "https://developer.hashicorp.com/vault/docs/configuration#log_level";
    };

    certificates = {

      organization = mkOption {
        type = str;
        description = "";
      };

      organizationUnit = mkOption {
        type = str;
        description = "";
      };

      country = mkOption {
        type = str;
        description = "";
      };

      province = mkOption {
        type = str;
        description = "";
      };

      locality = mkOption {
        type = str;
        description = "";
      };

      domain = mkOption {
        type = str;
        default = clusterInfo.fqdn;
        description = "";
      };

      issuer = mkOption {
        type = str;
        default =
          config.services.vault.cluster.certificates.organizationUnit
          + "/"
          + config.services.vault.cluster.certificates.organization;
        description = "";
      };

      path = {

        serverBase = mkOption {
          type = str; # use strings instead of paths to avoid copying to the nix store
          default = "/var/lib/vault/certs/";
          description = "Base path in which all certificates are stored.";
        };

        localBase = mkOption {
          type = str; # use strings instead of paths to avoid copying to the nix store
          default = config.services.vault.cluster.certificates.path.serverBase;
          description = "Base path in which the configuration scripts look for the scripts.";
        };

        caRootCertName = mkOption {
          type = str;
          default = config.services.vault.cluster.certificates.organization + "-root";
          description = ''
            Name of the Certificate Authority (CA) certificate file.
            The Vault TLS certificate has to be signed with this certificate.
          '';
        };

        vaultCertName = mkOption {
          type = str;
          default = config.services.vault.cluster.certificates.organization + "-vault";
          description = ''
            Name of the Vault TLS certificate.
            If this file was signed by an intermediate CA, append the certificate of that CA (and any other chained CAs) to the end of this file.
          '';
        };

        vaultKeyName = mkOption {
          type = str;
          default = config.services.vault.cluster.certificates.organization + "-vault";
          description = "Name of the private key of the Vault TLS certificate.";
        };

      };
    };
  };

  ###############################################

  config =

    let

      cfg = config.services.vault;

      # Set the listener config
      listeners = get.listeners this;
      defaultListener = (head listeners);
      defaultListenerAddress = "${get.hostFqdn this}:${toString defaultListener.port}";
      clusterPort = defaultListener.port + 1;
      remainingListeners = tail listeners;

      firewallPorts = (lists.forEach listeners (listener: listener.port)) ++ [ clusterPort ];

      # Set the certificate files
      basePath = cfg.cluster.certificates.path.serverBase;
      rootCaFile = basePath + cfg.cluster.certificates.path.caRootCertName + ".crt";
      tlsCert = basePath + cfg.cluster.certificates.path.vaultCertName + ".crt";
      tlsKey = basePath + cfg.cluster.certificates.path.vaultKeyName + ".key";

    in

    {
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

        # add the first listener to the default nixos config
        address = defaultListenerAddress;
        tlsCertFile = tlsCert;
        tlsKeyFile = tlsKey;
        listenerExtraConfig = ''
          tls_client_ca_file = "${rootCaFile}"
          redact_addresses = "true"
        '';

        # setup vault for cluster use
        extraConfig =
          let

            # If there are more than one listeners configured -> add them to the config
            remainingListenersConfig = lists.forEach remainingListeners (listener: ''
              listener "tcp"{
                address = "${get.hostFqdn this}:${listener.port}"
                tls_cert_file = "${tlsCert}"
                tls_key_file = "${tlsKey}"
                tls_client_ca_file = "${rootCaFile}"
              }
            '');

          in
          ''
            ui = "${if cfg.cluster.enableUi then "true" else "false"}"
            disable_mlock = "true"
            api_addr = "https://${defaultListenerAddress}"
            cluster_addr = "https://${get.hostFqdn this}:${toString clusterPort}"
            cluster_name  = "${cfg.cluster.clusterName}"
            introspection_endpoint = "false"
            log_level = "${cfg.cluster.logLevel}"

            ${builtins.concatStringsSep "\n\n" remainingListenersConfig}
          '';

        ##########################
        # Storage
        ##########################

        # reference architecture: https://developer.hashicorp.com/vault/tutorials/raft/raft-reference-architecture
        storageBackend = "raft"; # https://developer.hashicorp.com/vault/docs/configuration/storage/raft

        storageConfig =
          let
            # Get all listening addresses from all other vault servers and add them to the join stanzas
            # https://developer.hashicorp.com/vault/docs/configuration/storage/raft#retry_join
            joinStanzas = lists.flatten (
              lists.forEach (get.otherServers) (
                vaultServer:
                lists.forEach (get.listeners vaultServer) (listener: ''
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
