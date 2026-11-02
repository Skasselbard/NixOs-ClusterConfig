{
  inputs = {

    # Import nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Import Home Manager (override ClusterConfig's bundled version)
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
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
        # This registers the "secrets" cluster service, which projects
        # sops files into sops-nix secrets and templates.
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

                # Enable sops-nix-backed secrets on every machine in the cluster.
                # KeePass is not a runtime backend here; it is only an escrow
                # option for the age key that unlocks the sops files.
                secrets = {
                  selectors = [ filters.clusterMachines ];
                  # Convention: <flakeRoot>/secrets.
                  sopsRoot = ./secrets;
                  # The admin key source is both the recipient key for every
                  # generated rule and the identity used by key-holder commands.
                  adminKeySource = {
                    type = "age";
                    age.sourceKeyFile = "../00-exampleConfigs/secrets/age/admin.key";
                  };
                  # Group members share one sops file. This file is encrypted to
                  # the admin key and every member listed here.
                  groups.monitoring = [
                    "vm0"
                    "vm1"
                    "vm2"
                  ];

                  # Global cluster secret: no sopsFile means cluster.yaml.
                  # It is readable by every selected node plus the admin key.
                  secrets.cluster.clusterPassword = {
                    owner = "root";
                  };

                  # Group-scoped secret: the sopsFile shorthand selects the
                  # monitoring group file, readable by its members plus admin.
                  secrets.monitoring.token = {
                    sopsFile = "cluster/monitoring";
                    owner = "root";
                  };

                  templates.monitoringEnv = {
                    path = "/run/secrets/rendered/monitoring.env";
                    content = { config }: ''
                      TOKEN=${config.sops.placeholder."example/monitoring/token"}
                    '';
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

                  # Machine-scoped secrets live in secrets/example/machines/vm0.yaml.
                  # That file is encrypted only to vm0 and the admin key.
                  # file.path is a string on purpose: it must not be copied into
                  # the Nix store.
                  deployment.secrets.keySource = {
                    type = "age";
                    age.sourceKeyFile = "../00-exampleConfigs/secrets/age/vm0.key";
                  };
                  secrets = {
                    testService.testSecret = {
                      path = "/run/secrets/testService/testSecret";
                      mode = "0440";
                    };
                    admin.adminSecret = {
                      path = "/home/admin/secrets/adminSecret";
                      mode = "0400";
                    };
                  };

                  nixosModules = [
                    machines.vm0
                    inputs.disko.nixosModules.default
                    ../00-exampleConfigs/machines/hm-bug-workaround.nix
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

                  # vm1 is the Keepass escrow example. The entry password is the
                  # vm1 age private key; the public key is derived at runtime.
                  deployment.secrets.keySource = {
                    type = "keepass";
                    keepass = {
                      databasePath = "../00-exampleConfigs/secrets/Passwords.kdbx";
                      passwordFile = "../00-exampleConfigs/secrets/keepass.pass";
                    };
                  };
                  secrets.admin.testPassword = {
                    path = "/home/admin/secrets/testPassword";
                    mode = "0440";
                  };

                  # The service module is still enabled through the selector just like on the other machines.
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

                  # vm2 receives the service but has no machine-scoped secrets.
                  deployment.secrets.keySource = {
                    type = "age";
                    age.sourceKeyFile = "../00-exampleConfigs/secrets/age/vm2.key";
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
