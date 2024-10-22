{
  lib,
  pkgs,
  config,
  ...
}:

let
  str = lib.types.str;

  mkOption = lib.mkOption;

  initScript =
    let
      cfg = config.services.vault;
      basePath = cfg.cluster.certificates.path.serverBase;
      rootCaFile = basePath + cfg.cluster.certificates.path.caRootCertName + ".crt";
      # tlsCert = basePath + cfg.cluster.certificates.path.vaultCertName + ".crt";
      # tlsKey = basePath + cfg.cluster.certificates.path.vaultKeyName + ".key";
      endpoints = cfg.cluster.apiEndpoints;

    in
    ''
      #!/usr/bin/env bash
      set -e

      # Securely prompt for the Vault token
      read -s -p "Enter Vault Token: " VAULT_TOKEN
      echo

      if [ -z "$VAULT_TOKEN" ]; then
        echo "Error: Vault token cannot be empty."
        exit 1
      fi

      # Function to check if a Vault instance is available
      check_vault() {
        local vault_addr=$1
        echo "Checking Vault at $vault_addr ..."
        if curl -k --connect-timeout 5 -s "$vault_addr/v1/sys/health" | grep -q '"initialized":true'; then
          echo "Connected to Vault at $vault_addr"
          export VAULT_ADDR=$vault_addr
          return 0
        else
          echo "Vault at $vault_addr is not available."
          return 1
        fi
      }

      # Iterate over the Vault URIs and connect to the first available instance
      for uri in ${(lib.concatStringsSep " " endpoints)}; do
        if check_vault "$uri"; then
          break
        fi
      done

      if [ -z "$VAULT_ADDR" ]; then
        echo "Error: Could not connect to any Vault instance."
        exit 1
      fi

        VAULT_CACERT=${rootCaFile}

        # $ {
        #   let
        #     cfg = config.services.vault;
        #     sshCertificatesCfg = cfg.secretsEngines.sshCertificates;
        #     sshCertificateInit = if sshCertificatesCfg.enable then sshCertificatesCfg.initScript else "";
        #   in
        #   sshCertificateInit
        # }

        echo "Vault SSH secrets engine initialization complete."
    '';
in
{
  options.services.vault.initialization.script = mkOption {
    type = str;
    default = initScript;
  };

  imports = [ ./secretEngines/sshCeritficates.nix ];

}
