{ pkgs, lib, clusterlib, nixpkgs, colmena, flake-utils, nixos-generators, ... }:
let
  forEachAttrIn = clusterlib.forEachAttrIn;
  get = clusterlib.get;
in with pkgs.lib;

let

  # redefine types to nest submodules at the right place
  domainType = clusterlib.domainType { inherit clusterType; };
  clusterType = clusterlib.clusterType { inherit machineType; };

  # Defining deployment options for machines.
  # We import and reuse the colmena options
  machineType.options.deployment =
    let colmenaOptions = (import "${colmena.outPath}/src/nix/hive/options.nix");
    in attrsets.recursiveUpdate
    # import colmena deployment options
    (colmenaOptions.deploymentOptions {
      inherit lib;
      name = "{hostname}";
    }).options.deployment
    # overwrite colmena defaults
    {
      # targetHost.default = TODO: ?;
    };

  # build a bootable iso image from a machine configuration with nixos-generators
  bootImageNixosConfiguration = machineConfig:
    let
      nixosConfig = machineConfig.nixosConfiguration.config;

      interfaces = forEachAttrIn nixosConfig.networking.interfaces
        (interfaceName: interfaceDefinition:
          attrsets.getAttrs [ "useDHCP" "ipv4" "ipv6" ] interfaceDefinition);

      users = # filter some users that get created by default
        attrsets.filterAttrs (userName: userDefinition:
          !((strings.hasPrefix "nix" userName)
            || (strings.hasPrefix "systemd" userName)
            || builtins.elem userName [
              "backup"
              "messagebus"
              "nobody"
              "node-exporter"
              "root"
              "sshd"
            ])) nixosConfig.users.users;

      groups = # filter some groups that get created by default
        attrsets.filterAttrs (groupName: userDefinition:
          !((strings.hasPrefix "nix" groupName)
            || (strings.hasPrefix "systemd" groupName)
            || builtins.elem groupName [
              "backup"
              "cdrom"
              "dialout"
              "disk"
              "floppy"
              "input"
              "keys"
              "kmem"
              "log"
              "messagebus"
              "node-exporter"
              "nogroup"
              "root"
              "shadow"
              "sshd"
              "tape"
              "tty"
              "users"
              "wheel"
            ])) nixosConfig.users.groups;

    in {
      system = machineConfig.system;
      modules = [

        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"

        # force overwrite iso root with machine root to reuse passwords and ssh keys
        {
          users.users.root = lib.mkForce nixosConfig.users.users.root;
        }

        # useful settings to inherit from the machine configuration
        {
          # copy some useful locale settings
          console.font = nixosConfig.console.font;
          console.keyMap = nixosConfig.console.keyMap;
          i18n.defaultLocale = nixosConfig.i18n.defaultLocale;
          time.timeZone = nixosConfig.time.timeZone;

          # copy all interfaces and a selcetion of users
          networking.interfaces = interfaces;
          users.users = forEachAttrIn users
            # remove attributes that cannot be used on the installation environment
            (userName: userConfig:
              removeAttrs userConfig [ "shell" "cryptHomeLuks" ]);
          users.groups = groups;

          # Maybe some scripts could be copied for custom stuff?
          # isoImage.contents https://github.com/NixOS/nixpkgs/blob/27c13997bf450a01219899f5a83bd6ffbfc70d3c/nixos/modules/installer/cd-dvd/iso-image.nix#L543C5-L543C22
        }
      ];
    };

  # Build the deployment scripts and functions including
  # - nixosConfigurations for each machine
  # - minimal setup images in packages.$system.$machineName.iso
  deploymentAnnotation = config:
    let machines = get.machines config;
    in attrsets.recursiveUpdate config {

      nixosConfigurations = forEachAttrIn machines
        (machineName: machineConfig: machineConfig.nixosConfiguration);

      packages =
        # The deployment options are generated for all system  configurations (by using flake utils)
        (flake-utils.lib.eachSystem flake-utils.lib.allSystems (system: {

          packages = forEachAttrIn machines (machineName: machineConfig: {

            # buld an iso package for each machine configuration 
            iso = nixos-generators.nixosGenerate
              ((bootImageNixosConfiguration machineConfig) // {
                format = "iso";
              });

            # add a script to return the contents of the hardware configuration for each machine
            hardware-configuration = let
              cfg = machineConfig.deployment;
              host = cfg.targetHost;
              user = if cfg ? targetUser && cfg.targetUser != null then
                cfg.targetUser
              else
                "";
              port = if cfg ? targetPort && cfg.targetPort != null then
                ":" + cfg.targetPort
              else
                "";
              script =
                (pkgs.writeScriptBin "hardware-configuration-${machineName}"
                  "${pkgs.openssh}/bin/ssh ${user}@${host}${port} -t 'nixos-generate-config --show-hardware-config --no-filesystems'");
            in script;

          });

        })).packages;
    };
in {

  options.domain = domainType;
  config.extensions.deploymentTransformations = [ deploymentAnnotation ];
}
