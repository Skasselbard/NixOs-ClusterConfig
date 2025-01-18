{ lib, config, pkgs, ... }:

with lib;

let
  # Helper to generate secret paths
  generateSecretPath = account: secret: "/run/secrets/${account}/${secret}";
in {
  options = {
    secrets.backends = mkOption {
      type = with types; attrsOf (submodule {
        options = {
          enable = mkOption {
            type = bool;
            default = false;
            description = "Enable this secrets backend.";
          };
          config = mkOption {
            type = types.attrs;
            default = {};
            description = "Global configuration for the backend.";
          };
        };
      });
      default = {};
      description = "Configure secrets backends with global options.";
    };

    users.users = mkOption {
      type = attrsOf (submodule {
        options = {
          secrets = mkOption {
            type = attrsOf (submodule {
              options = {
                backend = mkOption {
                  type = types.str;
                  description = "The backend used to manage this secret.";
                };
                config = mkOption {
                  type = types.attrs;
                  default = {};
                  description = "Configuration specific to this secret.";
                };
              };
            });
            default = {};
            description = "Secrets for the user, organized by name.";
          };
        };
      });
      description = "User configurations, including secret management.";
    };
  };

  config = mkIf (config.secrets.backends != {}) {
    # Ensure /run/secrets exists
    systemd.tmpfiles.rules = [
      "d /run/secrets 0750 root root -"
    ];

    # Generate a script to distribute secrets
    systemd.services.secrets-distribution = {
      description = "Secrets Distribution Script Generation";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.bash}/bin/bash -c '${toString ./distribute-secrets.sh}'";
        Restart = "on-failure";
      };
    };

    # Generate script content
    generateSecretsScript = let
      enabledBackends = filterAttrs (_: v: v.enable) config.secrets.backends;
      userSecrets = mapAttrs (user: userConfig: 
        filterAttrs (_: secret: secret.backend != null) userConfig.secrets
      ) config.users.users;
    in pkgs.writeScript "distribute-secrets.sh" ''
      #!/usr/bin/env bash
      set -e

      echo "Distributing secrets to appropriate paths..."

      ${concatStringsSep "\n" (concatMap (user: secrets:
        concatMap (secretName: secret:
          let
            backendConfig = enabledBackends.${secret.backend}.config or {};
            path = generateSecretPath user secretName;
          in ''
            echo "Deploying secret ${secretName} for user ${user} to ${path}..."
            mkdir -p "$(dirname ${path})"
            chmod 750 "$(dirname ${path})"
            echo "Fetching secret from backend ${secret.backend}..."
            # Add backend-specific logic here
          ''
        ) (attrNames secrets)
      ) (attrNames userSecrets))}

      echo "Secrets distribution completed."
    '';
  };
}
