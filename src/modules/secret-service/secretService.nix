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

    services.secrets = {
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
          default = secretName: secretPath: "[ true ]";
          description = ''
            A function that takes the secret name and the secret path and returns a shell command string
            to validate the secret. For the file backend, this could check if the file exists and is readable.
          '';
        };
      };
      deriveEncryptionKey = mkOption {
        type = str;
        default =
          ''${pkgs.jq}/bin/jq .configHash | sha256sum | awk '{print $1}' '';
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
      };

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
