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

in
{
  options = {

    services.secrets = {
      deployment = {
        metadata.path = mkOption {
          type = str;
          default = "/var/lib/nixos-secret-service/deployment-info.json";
          description = ''
            Deployment location for the metadata file about the deployment.
          '';
        };
        database.path = mkOption {
          type = str;
          default = "/var/lib/nixos-secret-service/secrets.enc";
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
            path = mkOption {
              type = str;
              description = "Path to the secret for file-based backends.";
            };
          };
        };

        # backendOptions = {
        #   options = mkOption {
        #     type = attrsOf (submodule secretOptions);
        #     default = { };
        #     description = "Secrets for the user, organized by backend and name.";
        #   };
        # };

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
    {
      users.groups.secret-service = { };

      users.users.secret-service = {
        isSystemUser = true;
        description = "User for managing and deploying secrets.";
        home = "/var/lib/nixos-secret-service";
        group = "secret-service";
        extraGroups = [ "fuse" ];
      };

      systemd.tmpfiles.rules = [
        "d /run/nixos-secret-service 0750 root root -"
        "d /var/lib/nixos-secret-service 0700 root root -"
      ];
      environment.systemPackages = with pkgs; [ gocryptfs ];

      programs.fuse.userAllowOther = true;

      systemd.services.secret-service =
        let
          mountPath = "/dev/shm/nixos-secret-service/mount"; # Location where secrets are decrypted
          encryptedArchive = config.services.secrets.deployment.database.path; # Path to the encrypted file
          encryptionKeyCommand = "cat ${config.services.secrets.deployment.metadata.path} | ${config.services.secrets.deriveEncryptionKey}"; # Derives the encryption key
          users = attrNames (filterAttrs (_: v: v ? secrets && v.secrets != { }) config.users.users); # List of users with secrets

          decryptSecretsScript = pkgs.writeScript "decrypt-secrets.sh" ''
            #!/usr/bin/env bash
            set -e

            echo "Deriving encryption key..."
            ENCRYPTION_KEY=$(${encryptionKeyCommand})

            echo "Creating mount point..."
            mkdir -p ${mountPath}
            chmod 700 ${mountPath}
            chown "secret-service:secret-service" ${mountPath}

            echo "Mounting secrets file system..."
            userId=$(id -u secret-service)
            groupId=$(id -g secret-service)
            ${pkgs.gocryptfs}/bin/gocryptfs -quiet -extpass "echo $ENCRYPTION_KEY" ${encryptedArchive}  ${mountPath}

            echo "Setting up bind mounts for users..."
            for user in ${toString users}; do
              userMount="/dev/shm/nixos-secret-service/$user"
              mkdir -p "$userMount"
              chmod -R 777 "$userMount"
              chown "$user:secret-service" "$userMount"
              chown -R "$user:secret-service" "${mountPath}/$user"

              echo "Mounting secrets for $user..."
              userId=$(id -u $user)
              groupId=$(id -g secret-service)
              mount -o bind,ro,umask=0777 "${mountPath}/$user" "$userMount"
              # mount --make-private "$userMount"
            done

            echo "Secret Service started."
          '';

          stopSecretServiceScript = pkgs.writeScript "stop-secret-service.sh" ''
            #!/usr/bin/env bash
            set -e

            echo "Unmounting user secrets..."
            for user in ${toString users}; do
              userMount="/dev/shm/nixos-secret-service/$user"
              umount "$userMount" || true
              rmdir "$userMount" || true
            done

            echo "Unmounting decrypted archive..."
            fusermount -u ${mountPath} || true
            rmdir ${mountPath} || true

            echo "Secret Service stopped."
          '';

        in
        {
          description = "Secret Service for Mounting Decrypted Secrets in RAM";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          path = with pkgs; [
            archivemount
            bash
            coreutils
            gawk
            gnutar
            gocryptfs
            jq
            openssl
            util-linux
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${decryptSecretsScript}";
            ExecStop = "${stopSecretServiceScript}";
            RemainAfterExit = true;
            Restart = "on-failure";
          };
        };

    };
}
