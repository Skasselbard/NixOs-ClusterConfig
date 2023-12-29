{
  description = "A very basic flake"; # TODO:

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    disko = {
      url = "github:nix-community/disko/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };
  };

  outputs = { self, nixpkgs, disko, nixos-anywhere, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      lib = {
        # takes a list of disko devices definitions and returns  a devieces definition
        # accepted as a disko attribute
        mergeDiskoDevices = deviceDefinitions: {
          devices = with pkgs.lib.attrsets;
            (foldAttrs (item: acc: (recursiveUpdate item acc)) { }
              deviceDefinitions);
        };
        # takes a configuration with a partitioning configuration from this 
        # projects nixos modules and returns the command to run nixos anywhere
        deploy = {
          # the host configuration with the default nixos Module from this project included
          config,
          # the deployment tagret where niixos should be installed on
          ip,
          # if true the persistent storage will be formatted in addition to the ephemeral storage
          wipePersistentStorage ? false,
          # list of extra arguments (strings) passed to nixos anywhere
          extraArgs ? [ ] }:
          let
            formatScript = if wipePersistentStorage then
              config.partitioning.persistent_script
            else
              config.partitioning.ephemeral_script;
          in pkgs.writeScriptBin "deploy" ''
            ${pkgs.nix}/bin/nix run path:${nixos-anywhere.outPath} -- -s ${formatScript.outPath} ${config.system.build.toplevel.outPath} ${
              builtins.concatStringsSep " " extraArgs
            } root@${ip}
          '';
        formatScript = deviceDefinitions:
          (disko.lib.diskoScript {
            disko = (self.lib.mergeDiskoDevices deviceDefinitions);
          });
      };
      packages.${system} = {
        default = pkgs.writeScriptBin "staged-hive"
          "${pkgs.nushell}/bin/nu ${self}/scripts/hive.nu \${@:1}";
        # Concatinates a list of disko device definitions and build the corresponding format script
        # (including a whipe of the devices).
      };
      apps.${system} = {
        generation = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/hive-generate";
        };
      };
      nixosModules = {
        default = { config, pkgs, lib, ... }: {
          imports = [ "${self}/modules" ];
          _module.args.specialArgs.disko =
            disko; # TODO: Should it be done just because it can be done?
        };
        bootImage = { rootPasswd ? "setup", rootPasswdHash ? null
          , rootSSHKeys ? [ ], ip, ... }: {
            system = "x86_64-linux";
            modules = [
              "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              ({
                networking.usePredictableInterfaceNames =
                  false; # use ethX for interface names
                networking.interfaces.eth0.ipv4.addresses = [{
                  address = ip;
                  prefixLength = 24;
                }];
                users.users.root = {
                  password =
                    rootPasswd; # gets overwritten if hasedPassword is set
                  hashedPassword =
                    pkgs.lib.mkIf (rootPasswdHash != null) rootPasswdHash;
                  openssh.authorizedKeys.keys = rootSSHKeys;
                };
              })
            ];
            format = "iso";
          };
      };
    };
}
