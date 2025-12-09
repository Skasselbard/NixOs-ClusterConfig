{
  pkgs,
  lib,
  ...
}:
let

  attrsOf = lib.types.attrsOf;
  nullOr = lib.types.nullOr;
  rawType = lib.types.raw;
  str = lib.types.str;
  submodule = lib.types.submodule;

  mkOption = lib.mkOption;

  attrNames = lib.attrNames;
  concatMap = lib.concatMap;
  concatStringsSep = lib.concatStringsSep;
  filterAttrs = lib.filterAttrs;
  mapAttrs = lib.mapAttrs;
  mapAttrsToList = lib.mapAttrsToList;

  secretDeploymentScript =
    deploymentUser: deploymentHost: clusterConfig:
    let
      this = clusterConfig.clusters.this.machines.this;
      secretServiceName = this.config.systemd.services.secret-service.name;

      backends = clusterConfig.clusters.this.services.secrets.backends;
      userSecrets = mapAttrs (
        user: userConfig: filterAttrs (_: backendSecrets: backendSecrets != null) userConfig
      ) this.secrets;

      tmpPath = this.deployment.secrets.path.temp;
      persistentPath = this.deployment.secrets.path.persistent;
      databaseFileName = this.deployment.secrets.database.fileName;
      metadataFileName = this.deployment.secrets.metadata.fileName;
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
      ENCRYPTION_KEY=$(echo $METADATA | ${clusterConfig.clusters.this.services.secrets.deriveEncryptionKey})

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

  # Secrets can be defined for a machine user for each backend
  secretUserType = attrsOf (submodule backendTypeSubmodule);

  # generate secret options for each backend
  backendTypeSubmodule.options = mapAttrs (
    _: _:
    mkOption {
      # Multiple secrets can be defined in each backend
      type = attrsOf (submodule {
        options = {
          backendPath = mkOption {
            type = str;
            description = "Path to the secret as expected by the backend. E.g. simple file path for the 'file' backend.";
          };
          linkPath = mkOption {
            type = nullOr str;
            description = "Path on the remote machine. The mounted secret will be linked to this path (read only) with the corresponding user permission.";
            default = null;
          };
          permissions = mkOption {
            type = str;
            default = "400";
            description = "Permissions of the file. By default only readable by the owner.";
          };
        };
      });
    }
  ) backends;

  backends = {
    file = {
      retrieveSecretCommand = mkOption {
        type = rawType; # (types.str -> types.str -> types.str);
        default = secretName: secretPath: "cat ${secretPath}";
        description = ''
          A function that takes the secret name and the secret path and returns a shell command string
          to retrieve the secret. For the file backend, this could simply return content of the secret in the given path.
        '';
      };
      validateSecretCommand = mkOption {
        type = rawType; # (types.str -> types.str -> types.str);
        default = secretName: secretPath: "[ -f ${secretPath} -a -r ${secretPath} ]";
        description = ''
          A function that takes the secret name and the secret path and returns a shell command string
          to validate the secret. For the file backend, this could check if the file exists and is readable.
        '';
      };
    };
  };

in

{
  config.extensions = {

    clusterServices.secrets = {

      defaultModule = import ./secretService.nix;

      options = {

        inherit backends;

        deriveEncryptionKey = mkOption {
          type = str;
          default = ''${pkgs.jq}/bin/jq .configHash | sha256sum | ${pkgs.gawk}/bin/awk '{print $1}' '';
          description = ''
            A shell command that generates a deterministic encryption key. The default uses SHA-256.
          '';
        };
      };

    };

    clusterMachine = {

      options = {
        deployment = {
          secrets = {

            path = {
              persistent = mkOption {
                type = str;
                default = "/var/lib/nixos-secret-service";
                description = ''
                  Working directory for persisting encrypted files.
                '';
              };
              temp = mkOption {
                type = str;
                default = "/dev/shm/nixos-secret-service";
                description = ''
                  Working directory for persisting encrypted files.
                '';
              };
            };
            metadata.fileName = mkOption {
              type = str;
              default = "deployment-info.json";
              description = ''
                Deployment location for the metadata file about the deployment.
              '';
            };
            database.fileName = mkOption {
              type = str;
              default = "secrets.enc";
              description = ''
                Deployment location for the encrypted archive containing the secrets.
              '';
            };

          };
        };

        secrets = mkOption {
          description = ''
            Defines the secrets.

            Each secret is defined for a user and a backend.
            The In the example, secrets are defined for etcd and kubernetes user using the file backend.
          '';
          type = secretUserType;
          default = { };
          example = {
            etcd.file = {
              ca-cert = {
                backendPath = "./path/to/ca/etcd.crt";
                linkPath = "/path/on/remote/etcd.crt";
                permissions = "555";
              };
              ca-key = {
                backendPath = "./path/to/ca/etcd.key";
                linkPath = "/path/on/remote/etcd.key";
              };
            };
            kubernetes.file = {
              ca-cert = {
                backendPath = "./path/to/ca/kubernetes.crt";
                linkPath = "/path/on/remote/kubernetes.crt";
                permissions = "555";
              };
              ca-key = {
                backendPath = "./path/to/ca/kubernetes.key";
                linkPath = "/path/on/remote/kubernetes.key";
              };
            };
          };

        };
      };

      packages = {
        deploySecrets =
          { clusterConfig }:
          let
            this = clusterConfig.clusters.this.machines.this;
            deploymentConfig = this.deployment;
            nixosConfig = this.config;
            host = deploymentConfig.targetHost;
            secretServiceUser = nixosConfig.users.users.secret-service.name;
            deploymentUser =
              if deploymentConfig ? targetUser && deploymentConfig.targetUser != null then
                deploymentConfig.targetUser
              else
                "";
            rootUser = nixosConfig.users.users.root.name;
            deployCmd = user: host: "bash ${(secretDeploymentScript user host clusterConfig)}";
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
      };
    };
  };
}
