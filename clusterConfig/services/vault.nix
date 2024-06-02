{ selectors, roles, this }:
{ config, lib, pkgs, ... }:
let
  # client redirection
  apiAddress =
    "http://127.0.0.1:8200"; # https://developer.hashicorp.com/vault/docs/configuration#api_addr
  # request forwarding
  listenerAddress = "0.0.0.0:8200";
  # storagePath = "./vault/data";
  tlsCaFile = "/var/lib/vault/certs/skassel-root.crt";

in {
  options.services.vault = with lib;
    with lib.types; {

      enableUi = mkEnableOption (mdDoc "TODO:");

      clusterName = mkOption {
        type = nullOr str;
        default = null;
        description = lib.mdDoc
          "https://developer.hashicorp.com/vault/docs/configuration#cluster_name";
      };

      clusterAddress = mkOption {
        type = str;
        description = lib.mdDoc
          "https://developer.hashicorp.com/vault/docs/configuration#cluster_addr";
      };

      # certPath = mkOption {
      #   type = types.str;
      #   default = "/var/lib/vault/certs/";
      #   description = lib.mdDoc ''
      #     TODO:
      #     - search path for tls certificates and private key
      #     - cannot be handled by nix because private key needs to be private
      #   '';
      # };

      # loglevel = mkOption {
      #   type = types.enum [ "trace" "debug" "info" "warn" "error" ];
      #   default = "info";
      #   description = lib.mdDoc "TODO:";
      # };
    };
  config = let cfg = config.services.vault;
  in {
    environment.systemPackages = with pkgs; [ vault-bin certstrap openssl ];
    services.vault = {
      enable = true;
      package = pkgs.vault-bin;
      # reference architecture: https://developer.hashicorp.com/vault/tutorials/raft/raft-reference-architecture

      # TODO: remove after tests
      # dev = true;
      # devRootTokenID = "root";

      storageBackend =
        "raft"; # https://developer.hashicorp.com/vault/docs/configuration/storage/raft

      # TODO: joining? https://developer.hashicorp.com/vault/docs/configuration/storage/raft#retry_join-stanza
      storageConfig = ''
        node_id = "${config.networking.hostName}"
      '';

      extraConfig = let
        ui = if config.services.vault.enableUi then "true" else "false";
        clusterName = if cfg.clusterName == null then
          ""
        else
          ''cluster_name  = "${cfg.clusterName}"'';
        clusterAddress = cfg.clusterAddress;
      in ''
        ui = "${ui}"
        disable_mlock = "true"
        cluster_addr = "${clusterAddress}"
        ${clusterName}
        api_addr = "${apiAddress}"
        introspection_endpoint = "false"
        log_level = "info"
      '';
      # TODO: default_lease_ttl https://developer.hashicorp.com/vault/docs/configuration#default_lease_ttl
      # TODO: max_lease_ttl https://developer.hashicorp.com/vault/docs/configuration#max_lease_ttl
      # TODO request_limiter https://developer.hashicorp.com/vault/docs/configuration#request_limiter

      # TODO TLS configuration
      listenerExtraConfig = ''
        address = "${listenerAddress}"
        tls_client_ca_file = "${tlsCaFile}"
      '';

      # TODO: user lockout? https://developer.hashicorp.com/vault/docs/configuration#user_lockout
    };
  };

}
