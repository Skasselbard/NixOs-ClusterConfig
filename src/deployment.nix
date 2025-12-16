{
  pkgs,
  lib,
  clusterlib,
  flakeInputs,
  ...
}:
let
  attrsets = lib.attrsets;
  strings = lib.strings;

  forEachAttrIn = clusterlib.forEachAttrIn;
  get = clusterlib.get;

  colmena = flakeInputs.colmena;
  nixos-generators = flakeInputs.nixos-generators;

in

let
  colmenaOptions = (import "${colmena.outPath}/src/nix/hive/options.nix");

  # build a bootable iso image from a machine configuration with nixos-generators
  bootImageNixosConfiguration =
    machineConfig:
    let
      nixosConfig = machineConfig.config;

      interfaces = forEachAttrIn nixosConfig.networking.interfaces (
        interfaceName: interfaceDefinition:
        attrsets.getAttrs [
          "useDHCP"
          "ipv4"
          "ipv6"
        ] interfaceDefinition
      );

      wireless = # filter old options that are deprecated or cause conflicts
        attrsets.filterAttrs (
          optionName: optionDefinition:
          !(builtins.elem optionName [
            "environmentFile"
            "userControlled"
          ])
        ) nixosConfig.networking.wireless;

      users =
        let
          # filter some users that get created by default
          filteredUsers = attrsets.filterAttrs (
            userName: userDefinition:
            !(
              (strings.hasPrefix "nix" userName)
              || (strings.hasPrefix "systemd" userName)
              || builtins.elem userName [
                "backup"
                "messagebus"
                "nobody"
                "node-exporter"
                # "root"
                "sshd"
              ]
            )
          ) nixosConfig.users.users;
        in
        # only apply basic configuration and ignore complex or custom options
        forEachAttrIn filteredUsers (
          userName: userConfig: with userConfig; {
            inherit
              enable
              expires
              extraGroups
              group
              hashedPassword
              hashedPasswordFile
              initialHashedPassword
              initialPassword
              isNormalUser
              isSystemUser
              name
              openssh
              packages
              password
              subGidRanges
              uid
              ;
          }
        );

      groups = # filter some groups that get created by default
        attrsets.filterAttrs (
          groupName: userDefinition:
          !(
            (strings.hasPrefix "nix" groupName)
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
            ]
          )
        ) nixosConfig.users.groups;

    in
    {
      system = machineConfig.system;
      modules = [

        "${flakeInputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"

        # force overwrite iso root with machine root to reuse passwords and ssh keys
        { users.users.root = lib.mkForce users.root; }

        # useful settings to inherit from the machine configuration
        {
          environment.systemPackages = [
            pkgs.jq # needed for disko formatting
          ];

          # copy some useful locale settings
          console.font = nixosConfig.console.font;
          console.keyMap = nixosConfig.console.keyMap;
          i18n.defaultLocale = nixosConfig.i18n.defaultLocale;
          time.timeZone = nixosConfig.time.timeZone;

          # copy all interfaces
          networking.interfaces = interfaces;
          # TODO: nameservers and gateway!
          networking.wireless = wireless;

          # copy a selection of users
          users.users = users;
          users.groups = groups;

          # Maybe some scripts could be copied for custom stuff?
          # isoImage.contents https://github.com/NixOS/nixpkgs/blob/27c13997bf450a01219899f5a83bd6ffbfc70d3c/nixos/modules/installer/cd-dvd/iso-image.nix#L543C5-L543C22
        }
      ];
    };

  # Build the deployment scripts and functions including
  # - nixosConfigurations for each machine
  deploymentAnnotation =
    config:

    attrsets.recursiveUpdate config {
      # add nixos configurations to flake structure
      # otherwise the build commands have no target
      nixosConfigurations = forEachAttrIn (get.machines config) (
        machineName: machineConfig: machineConfig.nixosConfiguration
      );

    };

in
{
  config.extensions = {
    transformations.deploymentTransformations = [ deploymentAnnotation ];

    clusterMachine = {
      options.deployment =
        # We import and reuse the colmena options
        attrsets.recursiveUpdate
          # import colmena deployment options
          (colmenaOptions.deploymentOptions {
            inherit lib;
            name = "{hostname}";
          }).options.deployment
          # overwrite colmena defaults
          {
            # targetHost.default = TODO: ?;
          };

      packages = {
        build =
          { clusterConfig }:
          let
            machineName = clusterConfig.clusters.this.machines.this.name;
          in
          pkgs.writeShellScriptBin "build-${machineName}" "${pkgs.nixos-rebuild}/bin/nixos-rebuild --flake .#${machineName} build \${@:1}";

        deploy =
          { clusterConfig }:
          let
            this = clusterConfig.clusters.this.machines.this;
            machineName = this.name;
            cfg = this.deployment;
            host = cfg.targetHost;
            user = if cfg ? targetUser && cfg.targetUser != null then cfg.targetUser + "@" else "";
          in
          pkgs.writeShellScriptBin "deploy-${machineName}" "${pkgs.nixos-rebuild}/bin/nixos-rebuild --flake .#${machineName} switch --target-host '${user}${host}' \${@:1}";

        hardware-configuration =
          { clusterConfig }:
          let
            this = clusterConfig.clusters.this.machines.this;
            machineName = this.name;
            cfg = this.deployment;
            host = cfg.targetHost;
            user = if cfg ? targetUser && cfg.targetUser != null then cfg.targetUser + "@" else "";
            port = if cfg ? targetPort && cfg.targetPort != null then ":" + cfg.targetPort else "";
          in
          pkgs.writeShellScriptBin "hardware-configuration-${machineName}" "${pkgs.openssh}/bin/ssh ${user}${host}${port} -t 'nixos-generate-config --show-hardware-config --no-filesystems'";

        iso =
          { clusterConfig }:
          let
            this = clusterConfig.clusters.this.machines.this;
          in
          nixos-generators.nixosGenerate ((bootImageNixosConfiguration this) // { format = "iso"; });
      };
    };
  };

}
