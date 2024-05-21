{ selectors, roles, this }:
{ config, lib, pkgs, ... }:
let
  # client redirection
  apiAddress =
    "http://127.0.0.1:8200"; # https://developer.hashicorp.com/vault/docs/configuration#api_addr
  # request forwarding
  clusterAddress = "https://127.0.0.1:8201";
  listenerAddress = "0.0.0.0:8200";
  # storagePath = "./vault/data";
  nodeId = "lianli";
  clusterName = "Nixos BareMetal Vault";
  tlsCertFile = "/var/lib/vault/certs/skassel-intermediate-root.crt";
  tlsKeyFile = "/var/lib/vault/certs/skassel-intermediate-root.key";
  tlsCaFile = "/var/lib/vault/certs/skassel-root.crt";

in {
  # options = {
  #   dns = mkOption { };
  #   roles = mkOption {
  #     api = roleType;
  #     replicas = roleListType;
  #   };
  #   package = mkPackageOption pkgs "vault" { };
  #   config = with lib; {
  #     ui = mkEnableOption (lib.mdDoc "TODO:");
  #     certPath = mkOption {
  #       type = types.str;
  #       default = "/var/lib/vault/certs/";
  #       description = lib.mdDoc ''
  #         TODO:
  #         - search path for tls certificates and private key
  #         - cannot be handled by nix because private key needs to be private
  #       '';
  #     };

  #     loglevel = mkOption {
  #       type = types.enum [ "trace" "debug" "info" "warn" "error" ];
  #       default = "info";
  #       description = lib.mdDoc "TODO:";
  #     };
  #   };
  # };

  environment.systemPackages = with pkgs; [ vault-bin certstrap openssl ];
  services.vault = {
    enable = true;
    package = pkgs.vault-bin;
    # reference architecture: https://developer.hashicorp.com/vault/tutorials/raft/raft-reference-architecture

    # TODO: remove after tests
    dev = true;
    devRootTokenID = "root";

    inherit tlsCertFile;
    inherit tlsKeyFile;

    # storageBackend =
    #   "raft"; # https://developer.hashicorp.com/vault/docs/configuration/storage/raft

    # TODO: joining? https://developer.hashicorp.com/vault/docs/configuration/storage/raft#retry_join-stanza
    storageConfig = ''
      node_id = "${nodeId}"
    '';

    extraConfig = ''
      ui = "true"
      disable_mlock = "true"
      cluster_addr = "${clusterAddress}"
      cluster_name  = "${clusterName}"
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

}
