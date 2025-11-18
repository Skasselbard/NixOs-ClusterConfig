{
  description = "A very basic flake"; # TODO:

  inputs = {

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    disko = {
      url = "github:nix-community/disko/v1.12.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere/1.12.0";
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

    # kubernetes
    nix-kube-generators = {
      url = "github:farcaller/nix-kube-generators";
    };

    nixhelm = {
      url = "github:nix-community/nixhelm";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-anywhere,
      nixos-generators,
      nixhelm,
      nix-kube-generators,
      home-manager,
      colmena,
      flake-utils,
      ...
    }@inputs:

    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;
    in
    {

      lib =
        (import "${self}/src" {
          flakeInputs = inputs;
        })
        // (import "${self}/src/lib.nix" { inherit lib nixpkgs flake-utils; });

      clusterServices = {
        staticDns = import "${self}/src/services/dns/staticDns.nix";
        vault = import "${self}/src/services/vault/vaultService.nix";
        kubernetes = import "${self}/src/services/kubernetes/kubernetesService.nix";
        secret-service = import "${self}/src/services/secret-service/secretService.nix";
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
          imports = [ "${self}/src/modules/homeManager.nix" ];
        };

        # Makes a deployment script available (currently) for each machine
        # under 'clusterconfig.packages.{system}.{machinename}.setup'.
        # The script remotly deploys the machines sytem (build from the machine nixosConfiguration) to
        # a running linux machine reachable under '...{machineConfig}.deployment.targetHost'.
        # The currently running system will be overwritten.
        nixos-anywhere = {
          imports = [ "${self}/src/modules/nixosAnywhere.nix" ];
        };

        # Makes a colmena hive definition available under 'clusterConfig.colmena'.
        # Also adds an app deinition for colmena that makes colmena availablke in your flake by runnong
        # 'nix run .#colmena [colmena-sub-cmd] -- [colmenaOptions]'
        colmena = {
          imports = [ "${self}/src/modules/colmena.nix" ];
        };

        # Module to add scripts for vault initialization to the flake packages
        vault.imports = [ "${self}/src/services/vault/vaultClusterModule.nix" ];

        kubernetes.imports = [ "${self}/src/services/kubernetes/kubernetesClusterModule.nix" ];

        secret-service.imports = [ "${self}/src/services/secret-service/clusterModule.nix" ];

      };
    };
}
