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
  caBoot = true;

  caBootEnv = {
    # This environment is used to boot up a certificate authotity (CA) with an air gapped certificate.
    # See this tutorial for reference:
    # https://developer.hashicorp.com/vault/tutorials/secrets-management/pki-engine?variants=vault-deploy%2Aselfhosted
    environment.systemPackages = with pkgs; [ vault-bin certstrap openssl ];
    services.vault = {
      enable = true;
      package = pkgs.vault-bin;
      dev = true;
      devRootTokenID = "root";

      address = "http://127.0.0.1:8200";
      extraConfig = ''
        ui = "true"
        max_lease_ttl = "87600h"
      '';
    };
  };
  productionEnv = {
    environment.systemPackages = [ pkgs.vault-bin ];
    services.vault = {
      enable = true;
      package = pkgs.vault-bin;
      # reference architecture: https://developer.hashicorp.com/vault/tutorials/raft/raft-reference-architecture

      storageBackend =
        "raft"; # https://developer.hashicorp.com/vault/docs/configuration/storage/raft

      # TODO: joining? https://developer.hashicorp.com/vault/docs/configuration/storage/raft#retry_join-stanza
      storageConfig = ''
        node_id = "${nodeId}"
        retry_join {
          leader_tls_servername   = "<VALID_TLS_SERVER_NAME>"
          leader_api_addr         = "https://127.0.0.1:8200"
          leader_ca_cert_file     = "/opt/vault/tls/vault-ca.pem"
          leader_client_cert_file = "/opt/vault/tls/vault-cert.pem"
          leader_client_key_file  = "/opt/vault/tls/vault-key.pem"
        }
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
        tls_disable = "true"
      '';

      # TODO: user lockout? https://developer.hashicorp.com/vault/docs/configuration#user_lockout
    };

  };
in if caBoot then caBootEnv else productionEnv
