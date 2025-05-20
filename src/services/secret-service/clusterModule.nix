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

  secretDeploymentScript =
    deploymentUser: deploymentHost: nixosConfig:
    let
      secretServiceName = nixosConfig.systemd.services.secret-service.name;

      backends = nixosConfig.services.secrets.backends;
      userSecrets = mapAttrs (
        user: userConfig: filterAttrs (_: backendSecrets: backendSecrets != null) userConfig.secrets
      ) nixosConfig.users.users;

      tmpPath = nixosConfig.services.secrets.deployment.tempPath;
      persistentPath = nixosConfig.services.secrets.deployment.persistentPath;
      databaseFileName = nixosConfig.services.secrets.deployment.database.fileName;
      metadataFileName = nixosConfig.services.secrets.deployment.metadata.fileName;
      generateSecretPath = account: secret: "${tmpPath}/secrets/${account}/${secret}";
    in
    pkgs.writeScript "deploy-secrets.sh" ''
      #!/usr/bin/env bash
      set -eE

      cleanup() {
        trap - EXIT ERR
        echo "Deleting temp folder..."
        # Weird Workaround to get the path to fusermount
        # If we use the path from a pkg we get permission issues
        $(nix-shell -p gocryptfs --run 'which fusermount') -u ${tmpPath}/secrets
        rm -rf ${tmpPath}
      }
      trap cleanup EXIT ERR

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
                validateCommand = (backends.${backend}.validateSecretCommand secretName secretConfig.backendPath);
              in
              [
                ''
                  if ! ${validateCommand}; then
                    echo "Validation failed for secret '${secretName}' from user '${user}' at '${secretConfig.backendPath}'."
                    echo "Validation command: '${validateCommand}'"
                    echo "Aborting"
                    exit 1
                  fi
                ''
              ]
            ) (attrNames userSecrets."${user}"."${backend}")
          ) (attrNames userSecrets."${user}")
        ) (attrNames userSecrets)
      )}

      mkdir -p ${tmpPath}
      chmod 700 ${tmpPath}
      mkdir -p ${tmpPath}/secrets # Store unencrypted secrets here
      mkdir -p ${tmpPath}/${databaseFileName} # Encrypted folder

      echo "Generating metadata"
      DATE=$(date --iso-8601=seconds)
      CONFIG_HASH=${builtins.hashString "sha256" (builtins.toJSON userSecrets)}
      METADATA="{\"date\": \"$DATE\", \"configHash\": \"$CONFIG_HASH\"}" 
      ENCRYPTION_KEY=$(echo $METADATA | ${nixosConfig.services.secrets.deriveEncryptionKey})

      echo "Initializing encrypted folder..."
      ${pkgs.gocryptfs}/bin/gocryptfs -quiet -init -extpass "echo $ENCRYPTION_KEY" ${tmpPath}/${databaseFileName}
      ${pkgs.gocryptfs}/bin/gocryptfs -quiet -extpass "echo $ENCRYPTION_KEY" ${tmpPath}/${databaseFileName} ${tmpPath}/secrets

      ${concatStringsSep "\n" (
        concatMap (
          user:
          concatMap (
            backend:
            concatMap (
              secretName:
              let
                secretConfig = userSecrets."${user}"."${backend}"."${secretName}";
                targetPath = generateSecretPath user secretName;
                retrieveCommand = backends.${backend}.retrieveSecretCommand secretName secretConfig.backendPath;
              in
              [
                ''
                  echo "retrieving secret ${secretName}"
                  mkdir -p "$(dirname ${targetPath})"
                  ${retrieveCommand} | cat > ${targetPath}
                  chmod 700 ${targetPath}
                ''
              ]
            ) (attrNames userSecrets."${user}"."${backend}")
          ) (attrNames userSecrets."${user}")
        ) (attrNames userSecrets)
      )}

      echo "Writing deployment metadata..."
      ssh "${deploymentUser}@${deploymentHost}" "mkdir -p '${persistentPath}'"
      echo $METADATA | ssh "${deploymentUser}@${deploymentHost}" "cat > '${persistentPath}/${metadataFileName}'"
      ssh "${deploymentUser}@${deploymentHost}" chown secret-service '${persistentPath}/${metadataFileName}'

      echo "Copying archive to remote..."
      ${pkgs.rsync}/bin/rsync -avz --progress ${tmpPath}/${databaseFileName} "${deploymentUser}@${deploymentHost}:${persistentPath}"
      ssh "${deploymentUser}@${deploymentHost}" chown -R secret-service '${persistentPath}/${databaseFileName}'

      echo "Restarting ${secretServiceName}"
      ssh "${deploymentUser}@${deploymentHost}" systemctl restart ${secretServiceName}

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
              deployCmd = user: host: "bash ${(secretDeploymentScript user host nixosConfig)}";
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
