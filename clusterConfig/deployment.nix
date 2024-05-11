{ nixpkgs }:
let
  pkgs = import nixpkgs {
    # the exact value of 'system' should be unimportant since we only use lib
    system = "x86_64-linux";
  };
in with pkgs.lib;
let
  # helper functions
  forEachAttrIn = attrSet: function: (attrsets.mapAttrs function attrSet);
in {

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

      wheelUsers = attrsets.filterAttrs (userName: userDefinition:
        (builtins.elem "wheel" userDefinition.extraGroups
          || userDefinition.group == "wheel")) users;

    in {
      system = machineConfig.system;
      modules = [

        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
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
}
