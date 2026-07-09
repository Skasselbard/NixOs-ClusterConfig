{
  inputs = {

    # Import nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Import Home Manager.
    # By declaring it here and using `follows`, we override the version
    # bundled with ClusterConfig to ensure all inputs use the same nixpkgs.
    # The Home Manager version should match your nixpkgs channel (25.05 → release-25.05).
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Import the ClusterConfig flake.
    # Note: `inputs.home-manager.follows` ensures ClusterConfig uses
    # our Home Manager version above instead of its own.
    clusterConfigFlake = {
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      url = "github:Skasselbard/NixOs-ClusterConfig";
    };

    # Import disko for declarative disk partitioning
    disko = {
      url = "github:nix-community/disko/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      clusterConfigFlake,
      ...
    }:

    let # --- Imports and definitions ---

      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      filters = clusterConfigFlake.lib.filters;

      # Shared configuration (machines, secrets, Home Manager modules)
      configurations = (import ../00-exampleConfigs) { inherit pkgs; };
      secrets = configurations.secrets;
      machines = configurations.machines;

      # Home Manager modules imported from the shared config folder.
      # These are standard Home Manager modules (with `_class = "homeManager"`).
      homeModules = configurations.homeModules;

      #####################################################
      # ClusterConfig
      #####################################################
      clusterConfig = clusterConfigFlake.lib.buildCluster {

        modules = [
          clusterConfigFlake.clusterConfigModules.default
          clusterConfigFlake.clusterConfigModules.simple-dns
        ];

        domain = {
          suffix = "com";

          clusters = {

            example = {

              #############################################
              # Services
              services = {
                dns = {
                  roles.hosts = [ filters.clusterMachines ];
                  selectors = [ filters.clusterMachines ];
                };
              };

              ############################################
              # Users
              #
              # Home Manager modules are assigned per user via `homeManagerModules`.
              # IMPORTANT: Once ANY user has Home Manager modules, ALL users must
              # provide a module that sets `home.stateVersion`. Without it, Home
              # Manager will fail to evaluate.
              users = {

                root = {
                  # Even though root has no custom Home Manager config, we still
                  # include the default module which sets `home.stateVersion`.
                  homeManagerModules = [ homeModules.default ];

                  systemConfig = {
                    extraGroups = [ "wheel" ];
                    hashedPassword = secrets.pswdHash.root;
                    openssh.authorizedKeys.keys = [ secrets.ssh.publicKey ];
                  };
                };

                admin = {
                  # This user gets the starship prompt configuration via Home Manager.
                  # Modules are evaluated in order; `default` sets stateVersion,
                  # `starship` configures the starship shell prompt.
                  homeManagerModules = [
                    homeModules.default
                    homeModules.starship
                  ];

                  systemConfig = {
                    isNormalUser = true; # Creates a regular (non-root) user with a home directory
                    extraGroups = [ "wheel" ];
                    hashedPassword = secrets.pswdHash.admin;
                    openssh.authorizedKeys.keys = [ secrets.ssh.publicKey ];
                  };
                };
              };

              ############################################
              # Machines
              # Note: No formatScript is set, so `create` will skip formatting.
              # Use `deploy` (or colmena) to update already-installed machines.
              machines = {

                vm0 = {
                  inherit system;
                  deployment = {
                    targetHost = "192.168.122.200";
                  };
                  nixosModules = [
                    machines.vm0
                    inputs.disko.nixosModules.default
                    ../00-exampleConfigs/machines/hm-bug-workaround.nix
                  ];
                };

                vm1 = {
                  inherit system;
                  deployment = {
                    targetHost = "192.168.122.201";
                  };
                  nixosModules = [
                    machines.vm1
                    inputs.disko.nixosModules.default
                    ../00-exampleConfigs/machines/hm-bug-workaround.nix
                  ];
                };

                vm2 = {
                  inherit system;
                  deployment = {
                    targetHost = "192.168.122.202";
                  };
                  nixosModules = [
                    machines.vm2
                    inputs.disko.nixosModules.default
                    ../00-exampleConfigs/machines/hm-bug-workaround.nix
                  ];
                };

              };
            };

          };

        };
      };

    in
    # IMPORTANT: Return the clusterConfig directly as the flake output.
    clusterConfig;
}
