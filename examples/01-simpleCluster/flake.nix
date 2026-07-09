{
  inputs = {

    # Import nixpkgs - the NixOS package collection.
    # This defines the base set of packages and NixOS modules available.
    # Use the same major version across all inputs to avoid compatibility issues.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Import the ClusterConfig flake.
    # This is the framework that turns your cluster definition into
    # deployable NixOS machines.
    # `inputs.nixpkgs.follows` ensures it uses the same nixpkgs as above,
    clusterConfigFlake = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:Skasselbard/NixOs-ClusterConfig";
    };

    # Import disko for declarative disk partitioning.
    # Disko lets you define partition layouts in Nix and generates format scripts.
    # Required if you set `deployment.formatScript = "disko"` on any machine.
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

      # Build for 64-bit Linux. This is the only tested architecture so far.
      system = "x86_64-linux";

      # Import nixpkgs for the target system.
      pkgs = import nixpkgs { inherit system; };

      # Filters are functions that select machines from a cluster.
      # They are used in service selectors and roles to target specific machines.
      # Common filters:
      #   - filters.clusterMachines: selects all machines in the cluster
      #   - filters.hostname "name": selects a single machine by its hostname
      filters = clusterConfigFlake.lib.filters;

      # Import shared configuration from the examples config folder.
      # In a real project, you would define these in your own repository.
      # Keeping machine configs, secrets, and other configs separate from the
      # cluster definition improves readability and reusability.
      configurations = (import ../00-exampleConfigs) { inherit pkgs; };
      secrets = configurations.secrets;
      machines = configurations.machines;

    in
    let

      # --- Cluster Definition ---
      #
      # `buildCluster` is the main entry point of ClusterConfig.
      # It takes your cluster definition and produces:
      #   - NixOS system configurations (nixosConfigurations)
      #   - Deployment packages (build, deploy, create, iso, etc.)
      #   - Colmena hive configuration (for updates)
      #
      # The result is an attribute set you return directly as flake outputs.
      clusterConfig = clusterConfigFlake.lib.buildCluster {

        # --- Modules ---
        # ClusterConfig modules add features to the framework.
        # `default` includes: nixos-anywhere (initial deployment), colmena (updates),
        # and home-manager (per-user configuration).
        # Additional modules add cluster services like DNS.
        modules = [
          clusterConfigFlake.clusterConfigModules.default
          # The simple-dns module registers a "dns" cluster service.
          # It adds static IP addresses from configured machines to /etc/hosts,
          # so machines can resolve each other by hostname.
          clusterConfigFlake.clusterConfigModules.simple-dns
        ];

        domain = {

          # The suffix is appended to generate fully qualified domain names.
          # e.g. vm0.example.com (machine.cluster.suffix)
          suffix = "com";

          clusters = {

            # Each key here defines a cluster. The name "example" becomes:
            # - Part of the FQDN: <machine>.example.com
            # - The first segment in flake package paths: .#example.<machine>.<command>
            example = {

              # --- Cluster Services ---
              # Services are NixOS modules applied to multiple machines based on filters.
              # Unlike regular nixosModules (which target one machine), services can
              # consider the configuration of ALL machines in the cluster.
              #
              # Each service has:
              #   - selectors: filters that decide which machines RECEIVE the service module
              #   - roles: named groups of machines the service uses for its logic
              services = {
                dns = {
                  # The "hosts" role: all machines matching these filters contribute
                  # their static IPs to the DNS hosts file.
                  roles.hosts = [ filters.clusterNodes ];

                  # Selectors: machines matching these filters get the DNS service
                  # NixOS module injected (i.e., they receive the /etc/hosts entries).
                  selectors = [ filters.clusterNodes ];
                };
              };

              # --- Cluster Users ---
              # Users defined here are deployed on ALL machines in the cluster.
              # You can also define users per-machine in nixosModules;
              # avoid defining the same user in both places to prevent conflicts.
              #
              # Cluster users support two configuration layers:
              #   1. homeManagerModules: Home Manager modules for user-level config
              #   2. systemConfig: maps directly to NixOS `users.users.<name>`
              users = {

                # The key "root" becomes the username in NixOS (users.users.root).
                root = {
                  # Home Manager modules for this user.
                  # Empty list = no Home Manager configuration for root.
                  homeManagerModules = [ ];

                  # System-level user configuration.
                  # These options map directly to NixOS `users.users.root`.
                  systemConfig = {

                    extraGroups = [ "wheel" ];

                    # Hashed password (plaintext: 'root').
                    # Generate with: mkpasswd -m sha-512 <password>
                    hashedPassword = secrets.pswdHash.root;

                    # SSH public key for passwordless login.
                    openssh.authorizedKeys.keys = [ secrets.ssh.publicKey ];
                  };

                };

              };

              # --- Machines ---
              # Each key defines a machine in the cluster.
              # The key becomes the hostname of the machine.
              machines = {

                vm0 = {
                  # Target architecture for this machine.
                  inherit system;

                  # NixOS modules applied only to this machine.
                  # This is where you put your regular NixOS configuration
                  # (networking, partitions, packages, etc.).
                  nixosModules = [
                    machines.vm0 # Machine-specific config from ../00-exampleConfigs/
                    inputs.disko.nixosModules.default # Required when using disko partitioning
                  ];

                  deployment = {

                    # IP or hostname to reach this machine for deployment.
                    # This can differ from the machine's configured static IP.
                    # For example, you might deploy via a DHCP address to a machine
                    # that will be configured with a static IP.
                    targetHost = "192.168.122.200";

                    # Format the disk before installing NixOS.
                    # "disko" = auto-generate from the machine's disko config.
                    # null = skip formatting (for already formatted machines).
                    # You can also pass a custom script (see example 02).
                    formatScript = "disko";
                  };

                };

                vm1 =
                  let
                    # Advanced: You can reference the generated NixOS configuration
                    # using `self.nixosConfigurations`. Here we extract the static IP
                    # from the machine's NixOS config to avoid duplicating it.
                    # Be careful to avoid circular dependencies when doing this!
                    cfg = self.nixosConfigurations.vm1.config;
                    ip = (builtins.head cfg.networking.interfaces."eth0".ipv4.addresses).address;
                  in
                  {
                    inherit system;
                    nixosModules = [
                      machines.vm1
                      inputs.disko.nixosModules.default
                    ];

                    deployment = {
                      targetHost = ip;
                      formatScript = "disko";
                    };

                  };

                vm2 = {
                  inherit system;
                  nixosModules = [
                    machines.vm2
                    inputs.disko.nixosModules.default
                  ];

                  deployment = {
                    targetHost = "192.168.122.202";
                    formatScript = "disko";
                  };

                };

              };
            };

          };

        };
      };

    in
    # IMPORTANT: Return the clusterConfig directly as the flake output.
    # buildCluster produces a complete flake output set
    # (nixosConfigurations, packages, colmena hive, etc.)
    clusterConfig; # use the generated cluster config as the flake content
}
