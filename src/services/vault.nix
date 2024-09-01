{ selectors, roles, this }:
{ config, lib, pkgs, ... }:

with lib;

assert (builtins.isList roles.clusterAddress
  && (builtins.length roles.clusterAddress) == 1);

assert (builtins.isList roles.apiAddress && (builtins.length roles.apiAddress)
  == 1);

# assert config.services.vault.tlsCertFile == null
#   "'services.vault.tlsCertFile' is set but the vault-clusterConfig-service uses 'services.vault.certificates.vaultCert'";
# assert config.services.vault.tlsKeyFile == null
#   "'services.vault.tlsKeyFile' is set but the vault-clusterConfig-service uses 'services.vault.certificates.vaultCert'";

let

  # helper functions
  getListeners = host:
    if host.annotations.vaultListeners == null
    || host.annotations.vaultListeners == [ ] then [{
      address = "0.0.0.0";
      port = 8200;
    }] else
      host.annotations.vaultListeners;

in {
  options.services.vault = with lib.types; {

    enableUi = mkEnableOption
      (mdDoc "https://developer.hashicorp.com/vault/docs/configuration#ui");

    clusterName = mkOption {
      type = nullOr str;
      default = null;
      description = lib.mdDoc
        "https://developer.hashicorp.com/vault/docs/configuration#cluster_name";
    };

    clusterAddressPort = mkOption {
      type = port;
      description = lib.mdDoc ''
        Port for the cluster Adress:
        https://developer.hashicorp.com/vault/docs/configuration#cluster_addr

        The ip itself is resolved with the clusterAddress role.
      '';
      default = 8201;
    };

    apiAddressPort = mkOption {
      type = port;
      description = lib.mdDoc ''
        Port for the api Adress:
        https://developer.hashicorp.com/vault/docs/configuration#api_addr

        The ip itself is resolved with the ipAddress role.
      '';
      default = 8200;
    };

    certificates = {
      caRootCert = mkOption {
        type = types.str;
        default = "/var/lib/vault/certs/ca-root.cert";
        description = lib.mdDoc ''
          Path to the Certificate Authority (CA) certificate file.
          The Vault TLS certificate has to be signed with this certificate.

        '';
      };
      vaultCert = mkOption {
        type = types.str;
        default = "/var/lib/vault/certs/vault.cert";
        description = lib.mdDoc ''
          The Vault TLS certificate.
          If this file was signed by an intermediate CA, append the certificate of that CA (and any other chained CAs) to the end of this file.
        '';
      };
      vaultKey = mkOption {
        type = types.str;
        default = "/var/lib/vault/certs/vault.key";
        description = lib.mdDoc ''
          The private key of the Vault TLS certificate.
        '';
      };
    };

    # listeners = mkOption {
    #   description = mdDoc
    #     "A list of listener addresses and ports. The ports will be opend in the firewall";
    #   type = listOf (submodule {
    #     options = {
    #       address = mkOption {
    #         description = mdDoc "The address the listener listens on";
    #         type = str;
    #       };
    #       port = mkOption {
    #         description = mdDoc
    #           "The port the listener listens on. Will be opened in the firewall";
    #         type = port;
    #       };
    #     };
    #   });
    #   example = [
    #     {
    #       address = "192.168.1.1";
    #       port = 8200;
    #     }
    #     {
    #       address = "10.0.0.1";
    #       port = 8300;
    #     }
    #   ];
    #   default = [ ];
    # };

    logLevel = mkOption {
      type = types.enum [ "trace" "debug" "info" "warn" "error" ];
      default = "info";
      description = lib.mdDoc
        "https://developer.hashicorp.com/vault/docs/configuration#log_level";
    };
  };
  config = let
    cfg = config.services.vault;

    # Set the listener config
    listeners = getListeners this;
    defaultListenerAddress = (builtins.head cfg.listeners).address;
    defaultListenerPort = (builtins.head cfg.listeners).port;
    extraListeners = builtins.tail cfg.listeners;

    firewallPorts = lists.forEach cfg.listeners (listener: listener.port);

    # Set the certificate files
    rootCaFile = cfg.certificates.caRootCert;
    tlsCert = cfg.certificates.vaultCert;
    tlsKey = cfg.certificates.vaultKey;

    # Get all listening addresses from all other vault servers and add them to the join stanzas
    # https://developer.hashicorp.com/vault/docs/configuration/storage/raft#retry_join
    joinStanzas =
      # TODO: filter 'this' host
      lists.forEach selectors (vaultServer:
        let listeners = getListeners vaultServer;
        in lists.forEach listeners (listener: ''
          retry_join {
            leader_api_addr = "http://${listener.address}:${listener.port}"
            leader_ca_cert_file = "${cfg.certificates.caRootCert}"
            leader_client_cert_file = "${cfg.certificates.vaultCert}"
            leader_client_key_file = "${cfg.certificates.vaultKey}"
          }
        ''));

  in {
    networking.firewall.allowedTCPPorts = firewallPorts;

    environment.systemPackages = with pkgs; [ vault-bin certstrap openssl ];
    services.vault = {
      enable = true;
      package = pkgs.vault-bin;
      # reference architecture: https://developer.hashicorp.com/vault/tutorials/raft/raft-reference-architecture

      storageBackend =
        "raft"; # https://developer.hashicorp.com/vault/docs/configuration/storage/raft

      storageConfig = ''
        node_id = "${config.networking.hostName}"
        path = "TODO:"

        ${builtins.concatStringsSep "\n\n" joinStanzas}
      '';

      extraConfig = with builtins;
        let
          clusterAddress = if (head roles.clusterAddress).ips.all == [ ] then
            "127.0.0.1"
          else
            head (head roles.clusterAddress).ips.all;
          apiAddress = if (head roles.apiAddress).ips.all == [ ] then
            "127.0.0.1"
          else
            head (head roles.apiAddress).ips.all;
          ui = if cfg.enableUi then "true" else "false";
          clusterNameLine = if cfg.clusterName == null then
            ""
          else
            ''cluster_name  = "${cfg.clusterName}"'';
          clusterAddressLine =
            "https://${clusterAddress}:${toString cfg.clusterAddressPort}";
          apiAddressLine =
            "https://${apiAddress}:${toString cfg.apiAddressPort}";

          # If there are more than one listeners configured -> add them to the config
          extraListenersConfig = lists.forEach extraListeners (listener: ''
            listener "tcp"{
              address = "${listener.address}:${listener.port}"
              tls_cert_file = "${tlsCert}"
              tls_key_file = "${tlsKey}"
              tls_client_ca_file = "${rootCaFile}"
            }
          '');

        in ''
          ui = "${ui}"
          disable_mlock = "true"
          cluster_addr = "${clusterAddressLine}"
          ${clusterNameLine}
          api_addr = "${apiAddressLine}"
          introspection_endpoint = "false"
          log_level = "${cfg.logLevel}"

          ${builtins.concatStringsSep "\n\n" extraListenersConfig}
        '';

      # TODO: default_lease_ttl https://developer.hashicorp.com/vault/docs/configuration#default_lease_ttl
      # TODO: max_lease_ttl https://developer.hashicorp.com/vault/docs/configuration#max_lease_ttl
      # TODO request_limiter https://developer.hashicorp.com/vault/docs/configuration#request_limiter

      # add the first listener to the default nixos config
      address = "${defaultListenerAddress}:${toString defaultListenerPort}";
      tlsCertFile = tlsCert;
      tlsKeyFile = tlsKey;
      listenerExtraConfig = ''
        tls_client_ca_file = "${rootCaFile}"
        redact_addresses = "true"
      '';

      # TODO: user lockout? https://developer.hashicorp.com/vault/docs/configuration#user_lockout
    };
  };

}
