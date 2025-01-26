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

  secretDeploymentScript =
    deploymentUser: deploymentHost: nixosConfig:
    let
      backends = nixosConfig.services.secrets.backends;
      userSecrets = mapAttrs (
        user: userConfig: filterAttrs (_: backendSecrets: backendSecrets != null) userConfig.secrets
      ) nixosConfig.users.users;
    in
    pkgs.writeScript "deploy-secrets.sh" ''
      #!/usr/bin/env bash
      set -e

      ${concatStringsSep "\n" (
        mapAttrsToList (backend: backendConfig: ''
          echo "Requesting credentials for backend: ${backend}..."
        '') backends
      )}

      echo "Validating secrets..."
      ${concatStringsSep "\n" (
        concatMap (
          user:
          concatMap (
            backend:
            concatMap (
              secretName:
              let
                secretConfig = userSecrets."${user}"."${backend}"."${secretName}";
                validateCommand = (backends.${backend}.validateSecretCommand secretName secretConfig.path);
              in
              [
                ''
                  if ! ${validateCommand}; then
                    echo "Validation failed for secret ${secretName}."
                    echo "Aborting"
                    exit 1
                  fi
                ''
              ]
            ) (attrNames userSecrets."${user}"."${backend}")
          ) (attrNames userSecrets."${user}")
        ) (attrNames userSecrets)
      )}

      ${concatStringsSep "\n" (
        concatMap (
          user:
          concatMap (
            backend:
            concatMap (
              secretName:
              let
                secretConfig = userSecrets."${user}"."${backend}"."${secretName}";
                backendConfig = backends.${backend}.config or { };
                path = generateSecretPath user secretName;
                retrieveCommand = backends.${backend}.retrieveSecretCommand secretName secretConfig.path;
                targetPath = path;
              in
              [
                ''
                  echo "Deploying secret ${secretName} to remote machine..."
                  ssh "${deploymentUser}@${deploymentHost}" "mkdir -p \"$(dirname ${targetPath})\""
                  ${retrieveCommand} | ssh "${deploymentUser}@${deploymentHost}" "cat > \"${targetPath}\""
                  echo "Secret ${secretName} deployed to ${deploymentHost}:${targetPath}."
                ''
              ]
            ) (attrNames userSecrets."${user}"."${backend}")
          ) (attrNames userSecrets."${user}")
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
        ${nixosConfig.services.secrets.deriveEncryptionKey}
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
              deploymentConfig = machineConfig.deployment;
              nixosConfig = machineConfig.nixosConfiguration.config;
              host = deploymentConfig.targetHost;
              secretServiceUser = nixosConfig.users.users.secret-service.name;
              deploymentUser =
                if deploymentConfig ? targetUser && deploymentConfig.targetUser != null then
                  deploymentConfig.targetUser
                else
                  "";
              rootUser = nixosConfig.users.users.root.name;
              deployCmd =
                user: host:
                # "nix copy --to ssh://${user}@${host} ${(secretDeploymentScript user host nixosConfig)}; 
                "bash ${(secretDeploymentScript user host nixosConfig)}";
            in
            pkgs.writeScriptBin "connect-secrets.sh" ''
              #!/usr/bin/env bash
              set -e
              echo "Deploying Secrets to host: ${host}"

              echo
              echo "Trying to connect as user: ${secretServiceUser}"
              if ssh -o 'NumberOfPasswordPrompts 1' "${secretServiceUser}@${host}" "echo successfully connected"; then
                ${(deployCmd secretServiceUser host)}
                exit 0
              fi

              echo
              echo "Connection failed with user: ${secretServiceUser}. Trying deployment user: ${deploymentUser}"
              if ssh -o 'NumberOfPasswordPrompts 1' "${
                if deploymentUser != "" then deploymentUser + "@" else ""
              }${host}" "echo successfully connected"; then
                 ${(deployCmd deploymentUser host)}
                exit 0
              fi

              echo
              echo "Connection failed with deployment user: ${deploymentUser}. Trying root user: ${rootUser}"
              if ssh -o 'NumberOfPasswordPrompts 1' "${rootUser}@${host}" "echo successfully connected"; then
                ${(deployCmd rootUser host)}
                exit 0
              fi

              echo
              echo "Failed to deploy secrets. All connection attempts failed."
              exit 1
            '';

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
