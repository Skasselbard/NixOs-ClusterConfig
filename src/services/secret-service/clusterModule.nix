{
  config,
  pkgs,
  lib,
  flakeInputs,
  clusterlib,
  filters,
  ...
}:

let
  inherit (lib)
    mkOption
    types
    ;

  secretLib = import ./lib.nix { inherit lib pkgs; };
  scripts = import ./scripts.nix {
    inherit lib pkgs secretLib;
  };

  keySourceType = types.submodule {
    options = {
      type = mkOption {
        type = types.enum [
          "age"
          "keepass"
          "ssh"
          "native"
        ];
        default = "native";
        description = "How the node obtains its sops identity.";
      };
      targetKeyFile = mkOption {
        type = types.str;
        default = "/var/lib/sops-nix/key.txt";
        description = "Target-side age key file for managed age and Keepass sources.";
      };
      age.sourceKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Build-host age private key used to provision type age. Kept as a string so it is not copied into the Nix store.";
      };
      keepass.databasePath = mkOption {
        type = types.nullOr (types.either types.str types.path);
        default = null;
        description = "KeePass database used to escrow the age key.";
      };
      keepass.entry = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "KeePass entry containing the age key in its password field.";
      };
      keepass.passwordFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "File containing the KeePass database password. Kept as a string so it is not copied into the Nix store.";
      };
      keepass.passwordCommand = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Command that prints the KeePass database password.";
      };
      keepass.keyFilePath = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Optional KeePass key file.";
      };
      native.publicKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Public age recipient for type native.";
      };
      native.publicKeyFile = mkOption {
        type = types.nullOr (types.either types.str types.path);
        default = null;
        description = "File containing the public age recipient for type native.";
      };
      ssh.keyPaths = mkOption {
        type = types.listOf types.path;
        default = [ "/etc/ssh/ssh_host_ed25519_key" ];
        description = "SSH host keys used as age identities for type = \"ssh\".";
      };
    };
  };

  secretType = types.submodule {
    options = {
      sopsFile = mkOption {
        type = types.nullOr (types.either types.str types.path);
        default = null;
        description = "Sops file containing this secret. Defaults to the scope file.";
      };
      key = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Key path inside the sops file. Defaults to <user>/<secret>.";
      };
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime file name. Defaults to <user>/<secret>.";
      };
      path = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime symlink path. Defaults to /run/secrets/<name>.";
      };
      owner = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime owner. Defaults to the user attribute name.";
      };
      group = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime group.";
      };
      mode = mkOption {
        type = types.str;
        default = "0400";
        description = "Runtime mode in octal.";
      };
      format = mkOption {
        type = types.nullOr (
          types.enum [
            "yaml"
            "json"
            "binary"
            "dotenv"
            "ini"
          ]
        );
        default = null;
        description = "Sops format. All secrets in one file must use the same format.";
      };
      restartUnits = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Units restarted when the secret changes.";
      };
      reloadUnits = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Units reloaded when the secret changes.";
      };
      neededForUsers = mkOption {
        type = types.bool;
        default = false;
        description = "Install before users are created. Forces root ownership.";
      };
    };
  };

  templateType = types.submodule {
    options = {
      content = mkOption {
        type = types.raw;
        description = "Template content string or function of { config, lib, pkgs }.";
      };
      path = mkOption {
        type = types.str;
        description = "Runtime path for the rendered template.";
      };
      owner = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime owner.";
      };
      group = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime group.";
      };
      mode = mkOption {
        type = types.str;
        default = "0400";
        description = "Runtime mode in octal.";
      };
      restartUnits = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Units restarted when the template changes.";
      };
      reloadUnits = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Units reloaded when the template changes.";
      };
    };
  };

  secretServiceDefaults =
    config:
    clusterlib.update.nodes config (
      clusterName: nodeName: nodeConfig:
      let
        service = config.domain.clusters.${clusterName}.services.secrets or null;
        selected =
          if service == null then
            [ ]
          else
            filters.resolveNodeName (service.selectors or [ ]) clusterName config;
        keySource = nodeConfig.deployment.secrets.keySource;
      in
      if
        service == null
        || !(builtins.elem nodeName selected)
        || keySource.type != "keepass"
        || keySource.keepass.entry != null
      then
        { }
      else
        {
          deployment = nodeConfig.deployment // {
            secrets = nodeConfig.deployment.secrets // {
              keySource = keySource // {
                keepass = keySource.keepass // {
                  entry = "clusterConfig/${clusterName}/machines/${nodeName}";
                };
              };
            };
          };
        }
    );

  secretServiceNodes =
    config:
    clusterlib.update.nodes config (
      clusterName: nodeName: nodeConfig:
      let
        service = config.domain.clusters.${clusterName}.services.secrets or null;
        selected =
          if service == null then
            [ ]
          else
            filters.resolveNodeName (service.selectors or [ ]) clusterName config;
      in
      if service == null || !(builtins.elem nodeName selected) then
        { }
      else
        {
          nixosModules = [
            flakeInputs.sops-nix.nixosModules.sops
            (import ./secretService.nix {
              inherit
                service
                clusterName
                ;
              machine = nodeConfig;
              machineName = nodeName;
            })
          ] ++ (nodeConfig.nixosModules or [ ]);
        }
    );

  secretServiceExtraFiles =
    config:
    clusterlib.update.nodes config (
      _clusterName: _nodeName: nodeConfig:
      let
        keySource = nodeConfig.deployment.secrets.keySource;
        keepass = keySource.keepass;
        keepassEntry =
          if keepass.entry != null then
            keepass.entry
          else
            "clusterConfig/${_clusterName}/machines/${_nodeName}";
        keepassPassword =
          if keepass.passwordFile != null then
            "cat ${lib.escapeShellArg (toString keepass.passwordFile)}"
          else if keepass.passwordCommand != null then
            keepass.passwordCommand
          else
            "";
        keepassArgs = lib.optionalString (keepass.keyFilePath != null) (
          "--key-file ${lib.escapeShellArg (toString keepass.keyFilePath)}"
        );
        keepassCommand =
          if keepassPassword == "" then
            "${pkgs.keepassxc}/bin/keepassxc-cli show -q -s -a Password ${keepassArgs} ${lib.escapeShellArg (toString (keepass.databasePath or ""))} ${lib.escapeShellArg keepassEntry}"
          else
            "printf '%s\\n' \"$(${keepassPassword})\" | ${pkgs.keepassxc}/bin/keepassxc-cli show -q -s -a Password ${keepassArgs} ${lib.escapeShellArg (toString (keepass.databasePath or ""))} ${lib.escapeShellArg keepassEntry}";
        extraFiles =
          if keySource.type == "age" then
            {
              ${keySource.targetKeyFile} = {
                source = keySource.age.sourceKeyFile;
                mode = "0400";
              };
            }
          else if keySource.type == "keepass" then
            {
              ${keySource.targetKeyFile} = {
                command = keepassCommand;
                mode = "0400";
              };
            }
          else
            { };
      in
      if extraFiles == { } then
        { }
      else
        {
          deployment = (nodeConfig.deployment or { }) // {
            extraFiles = (nodeConfig.deployment.extraFiles or { }) // extraFiles;
          };
        }
    );

  machineSecretsType = types.submodule {
    freeformType = types.attrsOf (types.attrsOf secretType);
    options.templates = mkOption {
      type = types.attrsOf templateType;
      default = { };
      description = "Machine-scoped sops templates.";
    };
  };

  capitalize =
    name:
    if name == "" then
      name
    else
      lib.toUpper (builtins.substring 0 1 name) + builtins.substring 1 (builtins.stringLength name) name;

  groupPackageName =
    suffix: group:
    "secret${capitalize (builtins.replaceStrings [ "-" ] [ "_" ] group)}${suffix}";

  groupNames = lib.unique (
    builtins.concatMap (
      cluster: builtins.attrNames ((cluster.services.secrets or { }).groups or { })
    ) (builtins.attrValues config.domain.clusters)
  );

  groupPackages = builtins.listToAttrs (
    builtins.concatMap (
      group:
      [
        {
          name = groupPackageName "Edit" group;
          value =
            { clusterConfig }:
            pkgs.writeShellScriptBin (groupPackageName "Edit" group) (
              scripts.mkSecretEditScript {
                inherit clusterConfig group;
                scope = "cluster";
              }
            );
        }
        {
          name = groupPackageName "Set" group;
          value =
            { clusterConfig }:
            pkgs.writeShellScriptBin (groupPackageName "Set" group) (
              scripts.mkSecretSetScript {
                inherit clusterConfig group;
                scope = "cluster";
              }
            );
        }
        {
          name = groupPackageName "UpdateKeys" group;
          value =
            { clusterConfig }:
            pkgs.writeShellScriptBin (groupPackageName "UpdateKeys" group) (
              scripts.mkUpdateKeysScript {
                inherit clusterConfig group;
                rotate = false;
              }
            );
        }
        {
          name = groupPackageName "Rotate" group;
          value =
            { clusterConfig }:
            pkgs.writeShellScriptBin (groupPackageName "Rotate" group) (
              scripts.mkUpdateKeysScript {
                inherit clusterConfig group;
                rotate = true;
              }
            );
        }
      ]
    ) groupNames
  );

  serviceOptions = {
    sopsRoot = mkOption {
      type = types.path;
      description = "Root directory for sops files, conventionally <flakeRoot>/secrets.";
    };
    machinesSubDir = mkOption {
      type = types.str;
      default = "machines";
      description = "Subdirectory for per-machine sops files.";
    };
    clusterSubDir = mkOption {
      type = types.str;
      default = "cluster";
      description = "Subdirectory for group sops files.";
    };
    clusterSopsFile = mkOption {
      type = types.nullOr (types.either types.str types.path);
      default = null;
      description = "Explicit cluster-wide sops file. Defaults to <sopsRoot>/<cluster>/cluster.yaml.";
    };
    secrets = mkOption {
      type = types.attrsOf (types.attrsOf secretType);
      default = { };
      description = "Cluster-scoped secrets.";
    };
    templates = mkOption {
      type = types.attrsOf templateType;
      default = { };
      description = "Cluster-scoped templates.";
    };
    adminKeySource = mkOption {
      type = types.nullOr keySourceType;
      default = null;
      description = "Identity used by recipient-management commands.";
    };
    groups = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = { };
      description = "Shared group membership. A group named monitoring with members [ \"vm1\" \"vm2\" ] maps to cluster/monitoring.";
    };
    keepGenerations = mkOption {
      type = types.nullOr types.ints.unsigned;
      default = null;
      description = "Projected to sops.keepGenerations when non-null.";
    };
    useTmpfs = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = "Projected to sops.useTmpfs when non-null.";
    };
    log = mkOption {
      type = types.nullOr (
        types.listOf (
          types.enum [
            "trace"
            "debug"
            "info"
            "warn"
            "error"
          ]
        )
      );
      default = null;
      description = "Projected to sops.log when non-null.";
    };
    validateSopsFiles = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = "Projected to sops.validateSopsFiles when non-null.";
    };
    useSystemdActivation = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = "Projected to sops.useSystemdActivation when non-null.";
    };
    environment = mkOption {
      type = types.attrsOf (types.either types.str types.path);
      default = { };
      description = "Projected to sops.environment. Never put secret values here.";
    };
  };


in
{
  config.extensions = {
    transformations.clusterTransformations = [
      secretServiceDefaults
      secretServiceNodes
      secretServiceExtraFiles
    ];

    clusterServices.secrets = {
      defaultModule = { ... }: { };

      options = serviceOptions;

      packages = {
        secretsSyncKeyHolders =
          { clusterConfig }:
          pkgs.writeShellScriptBin "secretsSyncKeyHolders" (
            scripts.mkSyncKeyHoldersScript { inherit clusterConfig; }
          );

        secretEdit =
          { clusterConfig }:
          pkgs.writeShellScriptBin "secretEdit" (
            scripts.mkSecretEditScript {
              inherit clusterConfig;
              scope = "cluster";
            }
          );

        secretSet =
          { clusterConfig }:
          pkgs.writeShellScriptBin "secretSet" (
            scripts.mkSecretSetScript {
              inherit clusterConfig;
              scope = "cluster";
            }
          );

        secretUpdateKeys =
          { clusterConfig }:
          pkgs.writeShellScriptBin "secretUpdateKeys" (
            scripts.mkUpdateKeysScript {
              inherit clusterConfig;
              rotate = false;
            }
          );

        secretRotate =
          { clusterConfig }:
          pkgs.writeShellScriptBin "secretRotate" (
            scripts.mkUpdateKeysScript {
              inherit clusterConfig;
              rotate = true;
            }
          );
      } // groupPackages;
    };

    nodes = {
      options = {
        deployment.secrets.keySource = mkOption {
          type = keySourceType;
          default = { };
          description = "How this node obtains its sops identity.";
        };

        secrets = mkOption {
          type = machineSecretsType;
          default = { };
          description = "Machine-scoped secrets and templates.";
        };
      };

      packages = {
        secretsCheck =
          { clusterConfig }:
          let
            machineName = secretLib.machineNameOf clusterConfig;
          in
          scripts.mkCheckScript {
            inherit clusterConfig machineName;
          };

        secretsInstallKey =
          { clusterConfig }:
          let
            machineName = secretLib.machineNameOf clusterConfig;
          in
          pkgs.writeShellScriptBin "secretsInstallKey" (
            scripts.mkInstallKeyScript {
              inherit clusterConfig machineName;
            }
          );

        secretsRemoveOld =
          { clusterConfig }:
          let
            machineName = secretLib.machineNameOf clusterConfig;
          in
          pkgs.writeShellScriptBin "secretsRemoveOld" (
            scripts.mkRemoveOldScript {
              inherit clusterConfig machineName;
            }
          );

        secretsKeyGenerate =
          { clusterConfig }:
          let
            machineName = secretLib.machineNameOf clusterConfig;
          in
          pkgs.writeShellScriptBin "secretsKeyGenerate" (
            scripts.mkSecretsKeyGenerateScript {
              inherit clusterConfig machineName;
            }
          );

        secretEdit =
          { clusterConfig }:
          let
            machineName = secretLib.machineNameOf clusterConfig;
          in
          pkgs.writeShellScriptBin "secretEdit" (
            scripts.mkSecretEditScript {
              inherit clusterConfig machineName;
              scope = "machine";
            }
          );

        secretSet =
          { clusterConfig }:
          let
            machineName = secretLib.machineNameOf clusterConfig;
          in
          pkgs.writeShellScriptBin "secretSet" (
            scripts.mkSecretSetScript {
              inherit clusterConfig machineName;
              scope = "machine";
            }
          );
      };
    };
  };
}
