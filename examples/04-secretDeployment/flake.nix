{
  inputs = {

    # Import nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Import Home Manager (override ClusterConfig's bundled version)
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Import the ClusterConfig flake
    clusterConfigFlake = {
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      # url = "github:Skasselbard/NixOs-ClusterConfig";
      url = "path:../../";
    };

    # Import disko for declarative disk partitioning
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

      # Shared configuration (machines, secrets, Home Manager modules)
      configurations = (import ../00-exampleConfigs) { inherit pkgs; };
      secrets = configurations.secrets;
      machines = configurations.machines;
      homeModules = configurations.homeModules;

      #####################################################
      # ClusterConfig
      #####################################################
      clusterConfig = clusterConfigFlake.lib.buildCluster {

        # Load the `secret-service` module in addition to the defaults.
        # This registers the "secrets" cluster service, which:
        #   - Encrypts secret files into an archive (using gocryptfs)
        #   - Deploys the archive to the target machine
        #   - Decrypts and mounts secrets at runtime with per-user permissions
        modules = [
          clusterConfigFlake.clusterConfigModules.default
          clusterConfigFlake.clusterConfigModules.secret-service
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

                # Enable the secret-service on all machines in the cluster.
                # The secret-service module:
                #   1. Creates a `secret-service` system user and group
                #   2. Sets up gocryptfs for encrypted storage
                #   3. Runs a systemd service that decrypts and bind-mounts secrets
                #   4. Generates a `deploySecrets` package per machine
                secrets = {
                  selectors = [ filters.clusterMachines ];
                  backends.keepass = {
                    # The KeePass database is encrypted already, so using a Nix path here is acceptable.
                    # Nix copies the `.kdbx` file into the store and the deployment helper reads it from there.
                    # This is different from the `file` backend, where plain secret files must stay outside the store.
                    databasePath = ../00-exampleConfigs/secrets/Passwords.kdbx;
                    # For a real deployment you would usually replace this with a prompt, password file,
                    # or secret manager integration. The example uses a fixed value so the workflow is reproducible.
                    passwordCommand = "echo exampledb";
                    # Optional, if your database uses a key file in addition to the password.
                    # keyFilePath = /path/to/keyfile;
                  };

                };

              };

              ############################################
              # Users
              users = {

                root = {
                  homeManagerModules = [ homeModules.default ];
                  systemConfig = {
                    extraGroups = [ "wheel" ];
                    hashedPassword = secrets.pswdHash.root;
                    openssh.authorizedKeys.keys = [ secrets.ssh.publicKey ];
                  };
                };

                admin = {
                  homeManagerModules = [
                    homeModules.default
                    homeModules.starship
                  ];
                  systemConfig = {
                    isNormalUser = true;
                    extraGroups = [ "wheel" ];
                    hashedPassword = secrets.pswdHash.admin;
                    openssh.authorizedKeys.keys = [ secrets.ssh.publicKey ];
                  };
                };
              };

              ############################################
              # Machines
              machines = {

                vm0 = {
                  inherit system;
                  deployment = {
                    targetHost = "192.168.122.200";
                  };

                  # --- Secret definitions ---
                  # Secrets are defined per user and per backend.
                  # Structure: secrets.<user>.<backend>.<secretName>
                  #
                  # The `file` backend copies a local file as a secret.
                  # `backendPath` is the LOCAL path to the file on the deployment machine.
                  # The secret will be encrypted, deployed, and made available
                  # to the specified user on the target machine.
                  secrets = {
                    # Secrets for the "testService" system user.
                    # This user must exist on the machine (defined in nixosModules below).
                    testService.file = {
                      # IMPORTANT: Don't use nix paths like in this example in the file backend!!!!
                      # If you do your file will be added to the nix store and will be readable by anyone.
                      # I use this nix path here to easily include a file from the repo and the secret is not secret anyway.
                      # You should use only strings to configure file locations in production!
                      testSecret.backendPath = toString ../00-exampleConfigs/secrets/sshKey;
                    };
                    # Secrets for the "admin" cluster user.
                    admin.file = {
                      # IMPORTANT: Don't use nix paths like in this example in the file backend!!!!
                      # If you do your file will be added to the nix store and will be readable by anyone.
                      # I use this nix path here to easily include a file from the repo and the secret is not secret anyway.
                      # You should use only strings to configure file locations in production!
                      adminSecret.backendPath = toString ../00-exampleConfigs/secrets/sshKey;
                    };
                  };

                  nixosModules = [
                    machines.vm0
                    inputs.disko.nixosModules.default
                    # The "testService" user referenced in secrets above must exist.
                    # We define it inline here as a simple system user.
                    {
                      users.groups.testService = { };
                      users.users.testService = {
                        isNormalUser = false;
                        isSystemUser = true;
                        group = "testService";
                      };
                    }
                  ];
                };

                vm1 = {
                  inherit system;
                  deployment = {
                    targetHost = "192.168.122.201";
                  };

                  # `vm1` demonstrates the KeePass backend.
                  # All secrets below are resolved from the single database configured in
                  # `services.secrets.backends.keepass`, then staged locally, encrypted,
                  # copied to the target, and finally mounted for the `admin` user.
                  secrets = {
                    admin.keepass = {
                      # Read the KeePass password field from the entry.
                      testPassword = {
                        backendPath = "04-secretDeployment/TestPassword";
                        content = "password";
                        linkPath = "/home/admin/secrets/testPassword";
                        permissions = "440";
                      };

                      # Read the only attachment from the entry.
                      attachment = {
                        backendPath = "04-secretDeployment/TestAttachment";
                        content = "attachment";
                        linkPath = "/home/admin/secrets/attachment";
                      };

                      # Select a specific attachment when one entry contains several files.
                      login = {
                        backendPath = "04-secretDeployment/MultipleTestAttachments";
                        content = "attachment";
                        attachmentName = "Login.txt";
                        linkPath = "/home/admin/secrets/login";
                      };

                      personalData = {
                        backendPath = "04-secretDeployment/MultipleTestAttachments";
                        content = "attachment";
                        attachmentName = "PersonalData.txt";
                        linkPath = "/home/admin/secrets/personalData";
                      };
                    };
                  };

                  # The service module is still enabled through the selector just like on the other machines.
                  nixosModules = [
                    machines.vm1
                    inputs.disko.nixosModules.default
                  ];
                };

                vm2 = {
                  inherit system;
                  deployment = {
                    targetHost = "192.168.122.202";
                  };

                  # `vm2` receives the secret-service module but no secret definitions.
                  nixosModules = [
                    machines.vm2
                    inputs.disko.nixosModules.default
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
