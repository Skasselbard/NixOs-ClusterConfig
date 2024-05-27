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

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    colmena = {
      url = "github:zhaofengli/colmena/v0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, disko, nixos-anywhere, nixos-generators
    , home-manager, colmena, flake-utils, ... }@inputs:

    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {

      lib = (import ("${self}/clusterConfig") {
        inherit nixos-generators nixpkgs colmena flake-utils;
      }) // {

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
          # the deployment tagret where nixos should be installed on
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

        # Run a format script as root on a remote host.
        # Concatinates a list of disko device definitions and build the corresponding format script
        # (including a whipe of the devices).
        formatScript = {
          # the deployment tagret where nixos should be installed on
          ip,
          # list of extra arguments (strings) passed to ssh
          sshArgs ? [ "-t" ] }:
          deviceDefinitions:
          let
            script = disko.lib.diskoScript {
              disko = (self.lib.mergeDiskoDevices deviceDefinitions);
            } pkgs;
          in pkgs.writeScriptBin "deploy" ''
            echo "Format configured disko devicves?"
            echo "WARNING: all disk content will be erased if you select yes!"
            [[ ! "$(read -e -p "Y/n> "; echo $REPLY)" == [Yy]* ]] &&  echo "Canceld formating disko config." && exit
            echo "Formatting disko config."
            script=$(${pkgs.nix}/bin/nix build ${script} --print-out-paths)
            echo "Using script $script"
            ${pkgs.nix}/bin/nix copy --to "ssh://root@${ip}" "$script"
            ssh ${builtins.concatStringsSep " " sshArgs} root@${ip} $script
          '';

      };

      clusterServices = {

        staticDns = import "${self}/clusterConfig/services/staticDns.nix";

        vault = import "${self}/clusterConfig/services/vault.nix";
      };

      clusterConfigModules = {

        # Imports a selction of usefull deployment modules
        default = {
          imports = [
            self.clusterConfigModules.home-manager
            self.clusterConfigModules.nixos-anywhere
            self.clusterConfigModules.colmena
          ];
        };

        # Makes a list of 'homeManagerModules' available for the user configurations.
        # The home-amanager modules in that list will be added to the user configuration.
        # Each home-manager module should set '_class = "homeManager";' to be evaluated by home-manager
        # since this commit https://github.com/nix-community/home-manager/commit/26e72d85e6fbda36bf2266f1447215501ec376fd
        home-manager = {
          imports = [ "${self}/clusterConfig/modules/homeManager.nix" ];
          _module.args = { inherit home-manager; };
        };

        # Makes a deployment script available (currently) for each machine
        # under 'clusterconfig.packages.{system}.{machinename}.setup'.
        # The script remotly deploys the machines sytem (build from the machine nixosConfiguration) to 
        # a running linux machine reachable under '...{machineConfig}.deployment.targetHost'.
        # The currently running system will be overwritten.
        nixos-anywhere = {
          imports = [ "${self}/clusterConfig/modules/nixosAnywhere.nix" ];
          _module.args = { inherit nixos-anywhere; };
        };

        # Makes a colmena hive definition available under 'clusterConfig.colmena'.
        # Also adds an app deinition for colmena that makes colmena availablke in your flake by runnong
        # 'nix run .#colmena [colmena-sub-cmd] -- [colmenaOptions]'
        colmena = {
          imports = [ "${self}/clusterConfig/modules/colmena.nix" ];
          _module.args = { inherit colmena; };
        };
      };

      nixosModules = {

        default = { config, pkgs, lib, ... }: {
          imports = [ "${self}/modules" ];
          _module.args.specialArgs.disko =
            disko; # TODO: Should it be done just because it can be done?
        };

      };
    };
}
