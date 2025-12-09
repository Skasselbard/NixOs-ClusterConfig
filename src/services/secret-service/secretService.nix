{
  lib,
  config,
  pkgs,
  ...
}:

let
  attrNames = lib.attrNames;

  mapAttrsToList = lib.mapAttrsToList;
  concatStringsSep = lib.concatStringsSep;
  concatMap = lib.concatMap;

  secretsServiceConfig = config.clusterConfig.clusters.this.services.secrets;
  this = config.clusterConfig.clusters.this.machines.this;

  tmpPath = this.deployment.secrets.path.temp;
  persistentPath = this.deployment.secrets.path.persistent;
  databaseFileName = this.deployment.secrets.database.fileName;
  metadataFileName = this.deployment.secrets.metadata.fileName;
  mountPath = "${tmpPath}/mount"; # Location where secrets are decrypted
  encryptedArchive = "${persistentPath}/${databaseFileName}"; # Path to the encrypted file
  encryptionKeyCommand = "cat ${persistentPath}/${metadataFileName} | ${secretsServiceConfig.deriveEncryptionKey}"; # Derives the encryption key
in
{
  config = # mkIf (config.secrets.backends != { }) # TODO: disable config if no secrets are configured

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
          users = attrNames usersWithSecrets; # List of users with secrets
          usersWithSecrets = this.secrets;

          generateBindMountsScript =
            user: userCfg:
            let
              perBackend = mapAttrsToList (
                backend: secrets:
                let
                  userMount = "${tmpPath}/${user}";
                  setSecretPermissions = mapAttrsToList (
                    secret: secretCfg:
                    let
                      perm = secretCfg.permissions;
                      secretPath = "${mountPath}/${user}/${secret}";
                    in
                    ''
                      # Secret ${secret}
                      #-----------------
                      echo "Setting Permissions for secret '${secret}' for user '${user}'..."
                      if [ ! -f "${secretPath}" ]; then
                        echo "ERROR: Secret file '${secretPath}' does not exist"
                        exit 1
                      fi

                      chmod ${perm} "${secretPath}" || echo "WARN: Failed to chmod ${secretPath}"
                      chown ${user}:secret-service "${secretPath}" || echo "WARN: Failed to chown ${secretPath}"
                      #-----------------

                    ''
                  ) secrets;
                in
                ''
                  # User ${user}
                  ##############
                  if grep -q "${userMount}" /proc/mounts; then
                    echo "Cleaning up old mount at ${userMount}"
                    umount "${userMount}" || umount -l "${userMount}" || true
                    rmdir "${userMount}" || true
                  fi
                  if [ ! -d "${mountPath}/${user}" ]; then
                    echo "ERROR: Decrypted folder ${mountPath}/${user} does not exist"
                    exit 1
                  fi

                  mkdir -p "${userMount}"
                  chown "${user}:secret-service" "${userMount}"
                  chmod -R 550 "${userMount}"

                  ${concatStringsSep "\n" setSecretPermissions}

                  echo "Mounting secrets for ${user}..."
                  mount -o bind,ro "${mountPath}/${user}" "${userMount}"
                  ##############

                ''
              ) userCfg;

            in
            concatStringsSep "\n" (lib.flatten perBackend);

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
            ${concatStringsSep "\n" (mapAttrsToList generateBindMountsScript usersWithSecrets)}

            echo "Secret Service started."
          '';

          stopSecretServiceScript = pkgs.writeScript "stop-secret-service.sh" ''
            #!/usr/bin/env bash
            set -e

            bash ${unlinkSecretsScript}

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
                  userSecrets = usersWithSecrets.${user};
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
                      target = secretCfg.linkPath or null;
                    in
                    if target != null then
                      [
                        ''
                          echo "Linking ${source} -> ${target}"
                          mkdir -p -m 755 mkdir -p "$(dirname "${target}")"
                          ln -sf "${source}" "${target}"
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
                  userSecrets = usersWithSecrets.${user};
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
                      target = secretCfg.linkPath or null;
                    in
                    if target != null then
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
