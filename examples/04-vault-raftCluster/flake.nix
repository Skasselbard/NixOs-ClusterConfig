{
  inputs = {

    # Import nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

    # If you want to youse your own homeManager version you have to import it
    # and overwrite the version from NixOs-ClusterConfig.
    # This can be useful if you need a more current version of homeManager
    # than used by NixOs-ClusterConfig
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Import clusterConfig flake
    # Change this import to the github url
    clusterConfigFlake = {
      url = "path:../..";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Import disko to configure partitioning
    # If you want to use disko for formatting or device definitions, this option is required
    disko = {
      url = "github:nix-community/disko/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = inputs@{ self, nixpkgs, clusterConfigFlake, ... }:

    let # Definitions and imports

      system = "x86_64-linux";

      # import the pkgs attribute from the flake inputs
      pkgs = import nixpkgs { inherit system; };

      # The filters are used to resolve hosts when expanding the ClusterConfig
      filters = clusterConfigFlake.lib.filters;

      # Configuration from other Layers, e.g.: NixOs machine configurations
      configurations =
        (import "${self}/../00-exampleConfigs/") { inherit pkgs; };
      secrets = configurations.secrets;
      machines = configurations.machines;
      homeModules = configurations.homeModules;

      clusterConfig = clusterConfigFlake.lib.buildCluster {

        modules = [ clusterConfigFlake.clusterConfigModules.default ];

        domain = {
          suffix = "com";

          clusters = {

            # the cluster name will also be used for fqdn generation
            example = {

              services = {
                # Static DNS via /etc/hosts file
                dns = {
                  roles.hosts = [ filters.clusterMachines ];
                  selectors = [ filters.clusterMachines ];
                  definition = clusterConfigFlake.clusterServices.staticDns;
                };
              };

              users = {
                root = {
                  # If a user in your cluster uses HomeManager
                  # the ``home.stateVersion`` attribute has to be defined for all users 
                  homeManagerModules = [ homeModules.default ];
                  systemConfig = {
                    extraGroups = [ "wheel" ];
                    # 'root'
                    hashedPassword = secrets.pswdHash.root;
                    openssh.authorizedKeys.keys = [ secrets.ssh.publicKey ];
                  };
                };
                admin = {
                  # Add modules per user for HomeManager
                  homeManagerModules =
                    [ homeModules.default homeModules.starship ];
                  systemConfig = {
                    isNormalUser = true;
                    extraGroups = [ "wheel" ];
                    # 'admin'
                    hashedPassword = secrets.pswdHash.admin;
                    openssh.authorizedKeys.keys = [ secrets.ssh.publicKey ];
                  };
                };
              };

              machines = {

                vm0 = {
                  inherit system;
                  deployment = { targetHost = "192.168.122.200"; };
                  nixosModules = [
                    machines.vm0
                    # since the vms use disko for mounting, we still need to include the NixOs module
                    inputs.disko.nixosModules.default
                  ];
                };

                vm1 = {
                  inherit system;
                  deployment = { targetHost = "192.168.122.201"; };
                  nixosModules =
                    [ machines.vm1 inputs.disko.nixosModules.default ];
                };

                vm2 = {
                  inherit system;
                  deployment = { targetHost = "192.168.122.202"; };
                  nixosModules =
                    [ machines.vm2 inputs.disko.nixosModules.default ];
                };

              };
            };

          };

        };
      };

      # DO NOT FORGET!
    in clusterConfig; # use the generated cluster config as the flake content
}
