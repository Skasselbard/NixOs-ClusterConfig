{
  pkgs,
  lib,
  clusterlib,
  nixpkgs,
  ...
}:
let
  attrsets = lib.attrsets;
  strings = lib.strings;
  attrNames = lib.attrNames;
  concatMap = lib.concatMap;
  concatStringsSep = lib.concatStringsSep;
  filterAttrs = lib.filterAttrs;
  mapAttrs = lib.mapAttrs;
  mapAttrsToList = lib.mapAttrsToList;

  forEachAttrIn = clusterlib.forEachAttrIn;
  get = clusterlib.get;
  add = clusterlib.add;

  # Helper to generate secret paths
  generateSecretPath = account: secret: "/run/nixos-secret-service/deployment/${account}/${secret}";

  deploymentScript =
    machineConfig:
    let
      enabledBackends = filterAttrs (_: v: v.enable) machineConfig.secrets.backends;
      userSecrets = mapAttrs (
        user: userConfig: filterAttrs (_: backendSecrets: backendSecrets != null) userConfig.secrets
      ) machineConfig.users.users;
      deploymentConfig = machineConfig.secrets.deployment;
    in
    pkgs.writeScript "deploy-secrets.sh" ''
      #!/usr/bin/env bash
      set -e

      ${concatStringsSep "\n" (
        mapAttrsToList (backend: backendConfig: ''
          echo "Requesting credentials for backend: ${backend}..."
        '') enabledBackends
      )}

      echo "Validating secrets..."
      ${concatStringsSep "\n" (
        concatMap (
          user: secrets:
          concatMap (
            backend: backendSecrets:
            concatMap (
              secretName: secretConfig:
              let
                validateCommand = enabledBackends.${backend}.validateSecretCommand secretName secretConfig.path;
              in
              ''
                if ! ${validateCommand}; then
                  echo "Validation failed for secret ${secretName}."
                  echo "Aborting"
                  exit 1
                fi
              ''
            ) (attrNames backendSecrets)
          ) (attrNames secrets)
        ) (attrNames userSecrets)
      )}

      ${concatStringsSep "\n" (
        concatMap (
          user: secrets:
          concatMap (
            backend: backendSecrets:
            concatMap (
              secretName: secretConfig:
              let
                backendConfig = enabledBackends.${backend}.config or { };
                path = generateSecretPath user secretName;
                retrieveCommand = enabledBackends.${backend}.retrieveSecretCommand secretName secretConfig.path;
                targetPath = path;
              in
              ''
                echo "Fetching secret ${secretName} for user ${user} from backend ${backend}..."
                SECRET=$(${retrieveCommand})
                echo "Deploying secret ${secretName} to remote machine..."
                ${deploymentConfig.command targetPath}
                echo "Secret ${secretName} deployed to ${deploymentConfig.host}:${targetPath}."
              ''
            ) (attrNames backendSecrets)
          ) (attrNames secrets)
        ) (attrNames userSecrets)
      )}

      echo "Encrypting secrets to persistent storage..."
      METADATA_FILE="/var/lib/nixos-secret-service/deployment-info.yaml"
      ENCRYPTED_ARCHIVE="/var/lib/nixos-secret-service/secrets.enc"

      DATE=$(date --iso-8601=seconds)
      REVISION=$(nixos-version)
      CONFIG_HASH=$(nix-store --query --hash /run/current-system)

      echo "Writing deployment metadata..."
      cat > "$METADATA_FILE" <<EOL
      date: "$DATE"
      revision: "$REVISION"
      configHash: "$CONFIG_HASH"
      EOL

      echo "Generating encryption key..."
      ENCRYPTION_KEY=$(
        ${machineConfig.services.secrets.deployment.command}
      )

      echo "Encrypting deployment folder..."
      tar -cf - /run/nixos-secret-service/deployment | \
        openssl enc -aes-256-cbc -salt -out "$ENCRYPTED_ARCHIVE" -pass pass:"$ENCRYPTION_KEY"

      echo "Deleting deployment folder..."
      rm -rf /run/nixos-secret-service/deployment

      echo "Deployment completed."
    '';

in

let
  # Build the deployment scripts and functions including
  # - nixosConfigurations for each machine
  # - minimal setup images in packages.$system.$machineName.iso
  deploymentAnnotation =
    config:
    let

      buildScripts = add.machinePackages config (
        machineName: machineConfig: _config: {

          deploySecrets =
            let
              cfg = machineConfig.deployment;
              host = cfg.targetHost;
              user = if cfg ? targetUser && cfg.targetUser != null then cfg.targetUser + "@" else "";
            in
            pkgs.writeScriptBin "deploy-secrets-${machineName}" (deploymentScript machineConfig);

        }
      );
    in
    attrsets.recursiveUpdate buildScripts {

      nixosConfigurations = forEachAttrIn (get.machines config) (
        machineName: machineConfig: machineConfig.nixosConfiguration
      );

    };

in
{
  config.extensions = {
    deploymentTransformations = [ deploymentAnnotation ];
  };

}
