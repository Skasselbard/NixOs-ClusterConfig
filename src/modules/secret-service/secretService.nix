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

in
{
  options = {
    secrets.backends = mkOption {
      type = attrsOf (submodule {
        options = {
          enable = mkOption {
            type = bool;
            default = false;
            description = "Enable this secrets backend.";
          };
          config = mkOption {
            type = attrs;
            default = { };
            description = "Global configuration for the backend.";
          };
          retrieveSecretCommand = mkOption {
            type = rawType; # (types.str -> types.str -> types.str);
            description = ''
              A function that takes the secret name and the secret path and returns a shell command string
              to retrieve the secret. For the file backend, this could simply return content of the secret in the given path.
            '';
          };
          validateSecretCommand = mkOption {
            type = rawType; # (types.str -> types.str -> types.str);
            description = ''
              A function that takes the secret name and the secret path and returns a shell command string
              to validate the secret. For the file backend, this could check if the file exists and is readable.
            '';
          };
        };
      });
      default = { };
      description = "Configure secrets backends with global options.";
    };

    services.secrets = {
      deriveEncryptionKey = mkOption {
        type = str;
        default = ''echo -n "$REVISION-$DATE-$CONFIG_HASH" | sha256sum | awk '{print $1}'';
        description = ''
          A shell command that generates a deterministic encryption key. The default uses SHA-256.
        '';
      };
      deployment = {
        host = mkOption {
          type = str;
          description = "";
        };
        user = mkOption {
          type = str;
          default = "root";
          description = "";
        };
        command = mkOption {
          type = str;
          default =
            let
              host = config.services.secrets.deployment.host;
              user = config.services.secrets.deployment.user-ID;
            in
            (targetPath: ''
              ssh "${user}@${host}" "mkdir -p \"$(dirname ${targetPath})\" && echo -n $SECRET > \"${targetPath}\""
            '');
          description = "Function that generates a command to deploy a secret. The function takes the target path on the remote.";
        };
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

        backendOptions = {
          options = attrsOf (submodule secretOptions);
          default = { };
          description = "Secrets for the user, organized by backend and name.";
        };

        userOptions = {
          options.secrets = mkOption {
            type = attrsOf (submodule backendOptions);
            default = { };
            description = "Secrets for the user, organized by backend.";
          };
        };
      in
      mkOption { type = attrsOf (submodule userOptions); };
  };

  config = mkIf (config.secrets.backends != { }) {
    systemd.tmpfiles.rules = [
      "d /run/nixos-secret-service 0750 root root -"
      "d /var/lib/nixos-secret-service 0700 root root -"
    ];

    systemd.services.secret-service = {
      description = "Secret Service for Bind Mounting Secrets";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.bash}/bin/bash -c '/path/to/secret-service.sh'";
        Restart = "on-failure";
      };
    };

  };
}
