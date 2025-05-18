{
  lib,
  config,
  pkgs,
  ...
}:

let
  attrs = lib.types.attrs;
  attrsOf = lib.types.attrsOf;
  bool = lib.types.bool;
  package = lib.types.package;
  rawType = lib.types.raw;
  str = lib.types.str;
  submodule = lib.types.submodule;

  mkOption = lib.mkOption;
  mkIf = lib.mkIf;

  attrNames = lib.attrNames;
  filterAttrs = lib.filterAttrs;
  mapAttrs = lib.mapAttrs;

  concatMapStringsSep = lib.concatMapStringsSep;
  mapAttrsToList = lib.mapAttrsToList;
  escapeShellArg = lib.escapeShellArg;
  concatStringsSep = lib.concatStringsSep;
  concatMap = lib.concatMap;

in
{
  options = {

    services.secrets = {
      deployment = {
        persistentPath = mkOption {
          type = str;
          default = "/var/lib/nixos-secret-service";
          description = ''
            Working directory for persisting encrypted files.
          '';
        };
        tempPath = mkOption {
          type = str;
          default = "/dev/shm/nixos-secret-service";
          description = ''
            Working directory for persisting encrypted files.
          '';
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
      backends.file = {
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
      deriveEncryptionKey = mkOption {
        type = str;
        default = ''${pkgs.jq}/bin/jq .configHash | sha256sum | awk '{print $1}' '';
        description = ''
          A shell command that generates a deterministic encryption key. The default uses SHA-256.
        '';
      };
    };

    users.users =
      let
        secretOptions = {
          options = {
            config = mkOption {
              type = attrs;
              default = { };
              description = "Configuration specific to this secret.";
            };
            backendPath = mkOption {
              type = str;
              description = "Path to the secret as expected by the backend. E.g. simple file path for the 'file' backend.";
            };
            linkPath = mkOption {
              type = str;
              description = "Path on the remote machine. The mounted secret will be linked to this path (read only) with the corresponding user permission.";
            };
          };
        };

        userOptions = {
          options.secrets = mkOption {
            type = attrsOf (attrsOf (submodule secretOptions));
            default = { };
            description = "Secrets for the user, organized by backend.";
          };
        };
      in
      mkOption { type = attrsOf (submodule userOptions); };
  };

  config = # mkIf (config.secrets.backends != { }) # TODO: disable config if no secrets are configured
    let
      tmpPath = config.services.secrets.deployment.tempPath;
      persistentPath = config.services.secrets.deployment.persistentPath;
      databaseFileName = config.services.secrets.deployment.database.fileName;
      metadataFileName = config.services.secrets.deployment.metadata.fileName;
    in
    {
      users.groups.secret-service = { };

      users.users = {
        secret-service = {
          isSystemUser = true;
          description = "User for managing and deploying secrets.";
          home = persistentPath;
          group = "secret-service";
          extraGroups = [ "fuse" ];
        };
      };

      environment.systemPackages = with pkgs; [
        gocryptfs
        fuse
      ];

      programs.fuse.userAllowOther = true;

      systemd.services.secret-service =
        let
          mountPath = "${tmpPath}/mount"; # Location where secrets are decrypted
          encryptedArchive = "${persistentPath}/${databaseFileName}"; # Path to the encrypted file
          encryptionKeyCommand = "cat ${persistentPath}/${metadataFileName} | ${config.services.secrets.deriveEncryptionKey}"; # Derives the encryption key
          users = attrNames (filterAttrs (_: v: v ? secrets && v.secrets != { }) config.users.users); # List of users with secrets

          decryptSecretsScript = pkgs.writeScript "decrypt-secrets.sh" ''
            #!/usr/bin/env bash
            set -e

            echo "Deriving encryption key..."
            ENCRYPTION_KEY=$(${encryptionKeyCommand})

            if mountpoint -q ${mountPath}; then
              echo "Cleaning up old mount at ${mountPath}"
              fusermount -u ${mountPath} || umount -l ${mountPath}
            fi
            rm -rf ${mountPath}

            echo "Creating mount point..."
            mkdir -p ${mountPath}
            chmod 755 ${mountPath}
            chown "secret-service:secret-service" ${tmpPath}
            chown "secret-service:secret-service" ${mountPath}

            echo "Mounting secrets file system..."
            userId=$(id -u secret-service)
            groupId=$(id -g secret-service)
            if ! gocryptfs -allow_other -quiet -extpass "echo $ENCRYPTION_KEY" ${encryptedArchive} ${mountPath}; then
              echo "ERROR: Failed to mount gocryptfs"
              exit 1
            fi

            echo "Setting up bind mounts for users..."
            for user in ${toString users}; do
              userMount="${tmpPath}/$user"
              if grep -q "$userMount" /proc/mounts; then
                echo "Cleaning up old mount at $userMount"
                umount "$userMount" || umount -l "$userMount" || true
                rmdir "$userMount" || true
              fi
              if [ ! -d "${mountPath}/$user" ]; then
                echo "ERROR: Decrypted folder ${mountPath}/$user does not exist"
                exit 1
              fi
              mkdir -p "$userMount"
              chown "$user:secret-service" "$userMount"
              chown -R "$user:secret-service" "${mountPath}/$user"
              chmod -R 550 "$userMount"
              chmod -R 500 "${mountPath}/$user"

              echo "Mounting secrets for $user..."
              userId=$(id -u $user)
              groupId=$(id -g secret-service)
              mount -o bind,ro,umask=0500 "${mountPath}/$user" "$userMount"
            done

            echo "Secret Service started."
          '';

          stopSecretServiceScript = pkgs.writeScript "stop-secret-service.sh" ''
            #!/usr/bin/env bash
            set -e

            echo "Unmounting user secrets..."
            for user in ${toString users}; do
              userMount="${tmpPath}/$user"
              umount "$userMount" || umount -l "$userMount" || true
              rmdir "$userMount" || true
            done

            echo "Unmounting decrypted archive..."
            fusermount -u ${mountPath} || umount -l ${mountPath} || true
            rmdir ${mountPath} || true

            echo "Secret Service stopped."
          '';

          linkSecretsScript = pkgs.writeScript "link-secrets.sh" ''
            #!/usr/bin/env bash
            set -e

            echo "Linking secrets to user-specified paths..."

            ${concatStringsSep "\n" (
              concatMap (
                user:
                let
                  userSecrets = config.users.users.${user}.secrets;
                in
                concatMap (
                  backend:
                  let
                    secrets = userSecrets.${backend};
                  in
                  concatMap (
                    secret:
                    let
                      secretCfg = secrets.${secret};
                      source = "${tmpPath}/${user}/${secret}";
                      target = secretCfg.linkPath;
                    in
                    if secretCfg ? linkPath then
                      [
                        ''
                          echo "Linking ${source} -> ${target}"
                          mkdir -p -m 755 mkdir -p "$(dirname "${target}")"
                          ln -sf "${source}" "${target}"
                          chown -h "${user}:${user}" "${target}"
                          chmod -h 400 "${target}"  # Read-only
                        ''
                      ]
                    else
                      [ ]
                  ) (attrNames secrets)
                ) (attrNames userSecrets)
              ) users
            )}

            echo "All secret symlinks created."
          '';

          unlinkSecretsScript = pkgs.writeScript "unlink-secrets.sh" ''
            #!/usr/bin/env bash
            set -e

            echo "Removing secret symlinks..."

            ${concatStringsSep "\n" (
              concatMap (
                user:
                let
                  userSecrets = config.users.users.${user}.secrets;
                in
                concatMap (
                  backend:
                  let
                    secrets = userSecrets.${backend};
                  in
                  concatMap (
                    secret:
                    let
                      secretCfg = secrets.${secret};
                      target = secretCfg.linkPath;
                    in
                    if secretCfg ? linkPath then
                      [
                        ''
                          echo "Unlinking ${target}"
                          rm -f "${target}"
                        ''
                      ]
                    else
                      [ ]

                  ) (attrNames secrets)
                ) (attrNames userSecrets)
              ) users
            )}

            echo "All secret symlinks removed."
          '';

        in
        {
          description = "Secret Service for Mounting Decrypted Secrets in RAM";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          path = with pkgs; [
            bash
            coreutils
            gawk
            fuse
            gocryptfs
            jq
            util-linux
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${decryptSecretsScript}";
            ExecStartPost = "${linkSecretsScript}";
            ExecStopPre = "${unlinkSecretsScript}";
            ExecStop = "${stopSecretServiceScript}";
            # TODO: What is needed to run as non-root?
            # User = "secret-service";
            # Group = "secret-service";
            RemainAfterExit = true;
            Restart = "on-failure";
          };
        };

    };
}
