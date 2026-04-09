{
  inputs = {

    # Import nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # Import the ClusterConfig flake
    clusterConfigFlake = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:Skasselbard/NixOs-ClusterConfig";
    };

    # Import disko for declarative disk partitioning.
    # Required if you set `deployment.formatScript = "disko"` on any machine.
    disko = {
      url = "github:nix-community/disko/v1.12.0";
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

      # Shared configuration (machines, secrets) from the examples config folder
      configurations = (import ../00-exampleConfigs) { inherit pkgs; };
      secrets = configurations.secrets;
      machines = configurations.machines;

    in
    let

      clusterConfig = clusterConfigFlake.lib.buildCluster {

        modules = [
          clusterConfigFlake.clusterConfigModules.default
          clusterConfigFlake.clusterConfigModules.simple-dns
        ];

        domain = {
          suffix = "com";

          clusters = {

            example = {

              services = {
                dns = {
                  roles.hosts = [ filters.clusterMachines ];
                  selectors = [ filters.clusterMachines ];
                };
              };

              users.root.systemConfig = {
                extraGroups = [ "wheel" ];
                hashedPassword = secrets.pswdHash.root;
                openssh.authorizedKeys.keys = [ secrets.ssh.publicKey ];
              };

              machines = {

                # --- Option 1: No formatting ---
                # Setting formatScript to null (or leaving it unset) skips formatting.
                # The `create` command will install NixOS directly without touching partitions.
                # Use this when:
                #   - The machine is already formatted (e.g., from a previous deployment)
                #   - You want to format manually from the boot ISO
                # Note: Installing over an existing OS may work but is not recommended.
                vm0 = {
                  inherit system;
                  nixosModules = [
                    machines.vm0
                    inputs.disko.nixosModules.default
                  ];

                  deployment = {
                    targetHost = "192.168.122.200";
                    formatScript = null; # Explicitly skip formatting
                  };

                };

                # --- Option 2: Automatic disko formatting ---
                # Setting formatScript to "disko" generates a format script from the
                # machine's `disko.devices` configuration automatically.
                # This requires:
                #   - disko as a flake input
                #   - `inputs.disko.nixosModules.default` in nixosModules
                #   - A `disko.devices` attribute in the machine's NixOS config
                vm1 = {
                  inherit system;
                  nixosModules = [
                    machines.vm1
                    inputs.disko.nixosModules.default
                  ];

                  deployment = {
                    targetHost = "192.168.122.201";
                    formatScript = "disko"; # Auto-generate from disko config
                  };

                };

                # --- Option 3: Custom format script ---
                # You can pass any derivation (script) as formatScript.
                # This is useful when you want to:
                #   - Run custom commands before or after formatting
                #   - Format only specific partitions (e.g., OS but not data drives)
                #   - Use multiple disko configs and only format a subset
                #
                # Here we extract the disko-generated script and wrap it with
                # custom echo messages as a demonstration.
                vm2 = {
                  inherit system;
                  nixosModules = [
                    machines.vm2
                    inputs.disko.nixosModules.default
                  ];

                  deployment = {
                    targetHost = "192.168.122.202";

                    formatScript =
                      let
                        # Access the generated NixOS config via self.nixosConfigurations.
                        # The disko module exposes a `_disko` script under `disko.devices`.
                        cfg = self.nixosConfigurations.vm2.config;

                        # Pre-format message (your custom logic goes here)
                        customStartMessage = ''echo "This could be the result of your pre-format command"'';

                        # Extract the disko format script from the NixOS config.
                        # `cfg.disko.devices._disko` contains the generated script.
                        diskoScript = cfg.disko.devices._disko;

                        # Post-format message (your custom logic goes here)
                        customEndMessage = ''echo "This could be the result of your post-format command"'';

                      in
                      # Build an executable script that wraps the disko script
                      # with custom pre/post commands.
                      pkgs.writeScript "formatScript" ''
                        ${customStartMessage}
                        ${diskoScript}
                        ${customEndMessage}
                      '';
                  };

                };

              };
            };

          };

        };
      };

      # IMPORTANT: Return the clusterConfig directly as the flake output.
    in
    clusterConfig;
}
