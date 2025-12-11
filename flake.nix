{
  description = "A very basic flake"; # TODO:

  inputs = {

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
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
      url = "github:nix-community/nixos-generators/1.8.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
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

      clusterConfigModules = {

        # Imports a selection of useful deployment modules
        default = {
          imports = [
            self.clusterConfigModules.home-manager
            self.clusterConfigModules.nixos-anywhere
            self.clusterConfigModules.colmena
          ];
        };

        # definitions and scripts to generate tls certificates
        certificates = {
          imports = [ "${self}/src/modules/certificates/clusterModule.nix" ];
        };

        # Makes a colmena hive definition available under 'clusterConfig.colmena'.
        # Also adds an app definition for colmena that makes colmena available in your flake by running
        # 'nix run .#colmena [colmena-sub-cmd] -- [colmenaOptions]'
        colmena = {
          imports = [ "${self}/src/modules/colmena.nix" ];
        };

        # A module that populates the /etc/hosts file of each machine with selected machines in the cluster
        simpleDns = {
          imports = [ "${self}/src/services/dns.nix" ];
        };

        # Makes a list of 'homeManagerModules' available for the user configurations.
        # The home-manager modules in that list will be added to the user configuration.
        # Each home-manager module should set '_class = "homeManager";' to be evaluated by home-manager
        # since this commit https://github.com/nix-community/home-manager/commit/26e72d85e6fbda36bf2266f1447215501ec376fd
        home-manager = {
          imports = [ "${self}/src/modules/homeManager.nix" ];
        };

        kubernetes.imports = [ "${self}/src/services/kubernetes/kubernetesClusterModule.nix" ];

        secret-service.imports = [ "${self}/src/services/secret-service/clusterModule.nix" ];

        # Makes a deployment script available (currently) for each machine
        # under 'clusterConfig.packages.{system}.{machineName}.setup'.
        # The script remotely deploys the machines system (build from the machine nixosConfiguration) to
        # a running linux machine reachable under '...{machineConfig}.deployment.targetHost'.
        # The currently running system will be overwritten.
        nixos-anywhere = {
          imports = [ "${self}/src/modules/nixosAnywhere.nix" ];
        };

        # Module to add scripts for vault initialization to the flake packages
        vault.imports = [ "${self}/src/services/vault/vaultClusterModule.nix" ];
      };
    };
}
