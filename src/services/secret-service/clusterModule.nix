{
  pkgs,
  lib,
  ...
}:
let

  attrsOf = lib.types.attrsOf;
  enum = lib.types.enum;
  nullOr = lib.types.nullOr;
  rawType = lib.types.raw;
  str = lib.types.str;
  submodule = lib.types.submodule;

  mkOption = lib.mkOption;

  attrNames = lib.attrNames;
  concatMap = lib.concatMap;
  concatStringsSep = lib.concatStringsSep;
  escapeShellArg = lib.escapeShellArg;
  filterAttrs = lib.filterAttrs;
  mapAttrs = lib.mapAttrs;
  optionalString = lib.optionalString;
  optionals = lib.optionals;
  unique = lib.unique;

  keepassCli = pkgs.rustPlatform.buildRustPackage {
    pname = "secret-service-keepass-cli";
    version = "0.1.0";
    src = ./keepass-cli;
    cargoLock.lockFile = ./keepass-cli/Cargo.lock;
  };

  commonSecretOptions = {
    backendPath = mkOption {
      type = str;
      description = "Path to the secret as expected by the backend. E.g. a file path for the `file` backend or an entry path like `group/subgroup/entry` for the `keepass` backend.";
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

  keepassCommonArgs =
    backendConfig:
    concatStringsSep " " (
      [
        "--database"
        (escapeShellArg backendConfig.databasePath)
      ]
      ++ optionals (backendConfig.passwordFile != null) [
        "--password-file"
        (escapeShellArg backendConfig.passwordFile)
      ]
      ++ optionals (backendConfig.keyFilePath != null) [
        "--keyfile"
        (escapeShellArg backendConfig.keyFilePath)
      ]
    );

  keepassBatchPayload =
    requests:
    builtins.toJSON (
      builtins.map (request: {
        label = request.label;
        entryPath = request.secretConfig.backendPath;
        content = request.secretConfig.content;
        attachmentName = request.secretConfig.attachmentName;
      }) requests
    );

  backendDefinitions = {
    file = {
      secretOptions = { };
      serviceOptions = {
        prepareCommand = mkOption {
          type = rawType;
          default = _backendConfig: "";
          description = ''
            A function that takes the backend configuration and returns a shell snippet to prepare
            the backend before validation and retrieval.
          '';
        };
        retrieveSecretCommand = mkOption {
          type = rawType;
          default =
            requests: _backendConfig:
            concatStringsSep "\n" (
              builtins.map (request: ''
                echo "retrieving secret ${request.secretName}"
                mkdir -p "$(dirname ${escapeShellArg request.targetPath})"
                cat ${escapeShellArg request.secretConfig.backendPath} > ${escapeShellArg request.targetPath}
                chmod 700 ${escapeShellArg request.targetPath}
              '') requests
            );
          description = ''
            A function that takes all secret requests for a backend and the backend configuration,
            then returns a shell command string to retrieve them in one batch.
          '';
        };
        validateSecretCommand = mkOption {
          type = rawType;
          default =
            requests: _backendConfig:
            concatStringsSep "\n" (
              builtins.map (request: ''
                [ -f ${escapeShellArg request.secretConfig.backendPath} -a -r ${escapeShellArg request.secretConfig.backendPath} ] || {
                  echo "Validation failed for secret '${request.secretName}' from user '${request.user}' at '${request.secretConfig.backendPath}'."
                  exit 1
                }
              '') requests
            );
          description = ''
            A function that takes all secret requests for a backend and the backend configuration,
            then returns a shell command string to validate them in one batch.
          '';
        };
      };
    };

    keepass = {
      secretOptions = {
        content = mkOption {
          type = enum [
            "attachment"
            "password"
          ];
          default = "attachment";
          description = "Which part of the KeePass entry should be deployed. Defaults to `attachment` so file-like secrets such as certificates work out of the box.";
        };
        attachmentName = mkOption {
          type = nullOr str;
          default = null;
          description = "Optional attachment name inside the KeePass entry. Leave unset to use the only attachment on the entry.";
        };
      };
      serviceOptions = {
        prepareCommand = mkOption {
          type = rawType;
          default = backendConfig: ''
            ${optionalString (backendConfig.databasePath == "") ''
              echo "ERROR: services.secrets.backends.keepass.databasePath must be configured when KeePass secrets are used."
              exit 1
            ''}
            ${optionalString (backendConfig.passwordCommand != null) ''
              if [ -z "''${SECRET_SERVICE_KEEPASS_PASSWORD:-}" ]; then
                export SECRET_SERVICE_KEEPASS_PASSWORD="$(${backendConfig.passwordCommand})"
              fi
            ''}
          '';
          description = ''
            A function that takes the backend configuration and returns a shell snippet to prepare
            the backend before validation and retrieval.
          '';
        };
        databasePath = mkOption {
          type = str;
          default = "";
          description = "Path to the local KeePass `.kdbx` database that should be queried during secret deployment.";
        };
        passwordFile = mkOption {
          type = nullOr str;
          default = null;
          description = "Optional local file containing the KeePass database password.";
        };
        passwordCommand = mkOption {
          type = nullOr str;
          default = null;
          description = "Optional shell command that prints the KeePass database password during deployment. The password is exported as `SECRET_SERVICE_KEEPASS_PASSWORD` for the helper CLI.";
        };
        keyFilePath = mkOption {
          type = nullOr str;
          default = null;
          description = "Optional KeePass key file used in addition to or instead of a password.";
        };
        retrieveSecretCommand = mkOption {
          type = rawType;
          default =
            requests: backendConfig:
            let
              requestPayload = keepassBatchPayload requests;
            in
            ''
              cat <<'EOF_KEEPASS_BATCH' | ${keepassCli}/bin/secret-service-keepass batch-read ${keepassCommonArgs backendConfig} > "$KEEPASS_BATCH_RESPONSE_PATH"
              ${requestPayload}
              EOF_KEEPASS_BATCH

              ${pkgs.jq}/bin/jq -r '.[] | [.label, .dataBase64] | @tsv' "$KEEPASS_BATCH_RESPONSE_PATH" | while IFS=$'\t' read -r label dataBase64; do
                targetPath="$TMP_SECRET_ROOT/$label"
                mkdir -p "$(dirname "$targetPath")"
                printf '%s' "$dataBase64" | ${pkgs.coreutils}/bin/base64 --decode > "$targetPath"
                chmod 700 "$targetPath"
              done
            '';
          description = ''
            Reads all requested KeePass secrets in one batch and writes them into the deployment staging directory.
          '';
        };
        validateSecretCommand = mkOption {
          type = rawType;
          default =
            requests: backendConfig:
            let
              requestPayload = keepassBatchPayload requests;
            in
            ''
              cat <<'EOF_KEEPASS_BATCH' | ${keepassCli}/bin/secret-service-keepass batch-validate ${keepassCommonArgs backendConfig}
              ${requestPayload}
              EOF_KEEPASS_BATCH
            '';
          description = ''
            Validates that the KeePass database can be unlocked and that all configured entry content exists.
          '';
        };
      };
    };
  };

  backends = mapAttrs (_: backendDefinition: backendDefinition.serviceOptions) backendDefinitions;

  secretDeploymentScript =
    deploymentUser: deploymentHost: clusterConfig:
    let
      this = clusterConfig.clusters.this.machines.this;
      secretServiceName = this.config.systemd.services.secret-service.name;

      tmpPath = this.deployment.secrets.path.temp;
      persistentPath = this.deployment.secrets.path.persistent;
      databaseFileName = this.deployment.secrets.database.fileName;
      metadataFileName = this.deployment.secrets.metadata.fileName;
      generateSecretPath = account: secret: "${tmpPath}/secrets/${account}/${secret}";

      backends = clusterConfig.clusters.this.services.secrets.backends;
      userSecrets = mapAttrs (
        user: userConfig: filterAttrs (_: backendSecrets: backendSecrets != null) userConfig
      ) this.secrets;
      usedBackends = unique (concatMap (user: attrNames userSecrets."${user}") (attrNames userSecrets));
      keepassBatchResponsePath = "${tmpPath}/keepass-batch-response.json";
      backendSecretRequests =
        backend:
        concatMap (
          user:
          if builtins.hasAttr backend userSecrets."${user}" then
            concatMap (
              secretName:
              let
                secretConfig = userSecrets."${user}"."${backend}"."${secretName}";
              in
              [
                {
                  inherit user secretName secretConfig;
                  label = "${user}/${secretName}";
                  targetPath = generateSecretPath user secretName;
                }
              ]
            ) (attrNames userSecrets."${user}"."${backend}")
          else
            [ ]
        ) (attrNames userSecrets);
    in
    pkgs.writeScript "deploy-secrets.sh" ''
      #!/usr/bin/env bash
      set -eE

      cleanup() {
        trap - EXIT ERR
        echo "Deleting temp folder..."
        # Weird Workaround to get the path to fusermount
        # If we use the path from a pkg we get permission issues
        if [ -d ${tmpPath}/secrets ]; then
          $(nix-shell -p gocryptfs --run 'which fusermount') -u ${tmpPath}/secrets || true
        fi
        rm -rf ${tmpPath}
        unset SECRET_SERVICE_KEEPASS_PASSWORD || true
      }
      trap cleanup EXIT ERR

      export TMP_SECRET_ROOT=${escapeShellArg "${tmpPath}/secrets"}
      export KEEPASS_BATCH_RESPONSE_PATH=${escapeShellArg keepassBatchResponsePath}

      ${concatStringsSep "\n" (
        builtins.map (
          backend:
          let
            backendConfig = backends.${backend};
            prepareCommand = backendConfig.prepareCommand backendConfig;
          in
          ''
            echo "Preparing backend: ${backend}..."
            ${prepareCommand}
          ''
        ) usedBackends
      )}

        mkdir -p ${tmpPath}
        chmod 700 ${tmpPath}

      echo "Validating secrets..."
      ${concatStringsSep "\n" (
        builtins.map (
          backend:
          let
            backendConfig = backends.${backend};
            backendRequests = backendSecretRequests backend;
            validateCommand = backendConfig.validateSecretCommand backendRequests backendConfig;
          in
          ''
            echo "Validating backend: ${backend}"
            if ! ${validateCommand}; then
              echo "Validation failed for backend '${backend}'."
              echo "Validation command: '${validateCommand}'"
              echo "Aborting"
              exit 1
            fi
          ''
        ) usedBackends
      )}

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
        builtins.map (
          backend:
          let
            backendConfig = backends.${backend};
            backendRequests = backendSecretRequests backend;
            retrieveCommand = backendConfig.retrieveSecretCommand backendRequests backendConfig;
          in
          ''
            echo "Retrieving backend: ${backend}"
            if ! ${retrieveCommand}; then
              echo "Retrieval failed for backend '${backend}'."
              echo "Read command: '${retrieveCommand}'"
              echo "Aborting"
              exit 1
            fi
          ''
        ) usedBackends
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
    _: backendDefinition:
    mkOption {
      # Multiple secrets can be defined in each backend
      type = attrsOf (submodule {
        options = commonSecretOptions // backendDefinition.secretOptions;
      });
    }
  ) backendDefinitions;

in

{
  config.extensions = {

    clusterServices.secrets = {

      defaultModule = import ./secretService.nix;

      options = {

        inherit backends;

        deriveEncryptionKey = mkOption {
          type = str;
          default = "${pkgs.jq}/bin/jq .configHash | sha256sum | ${pkgs.gawk}/bin/awk '{print $1}' ";
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
