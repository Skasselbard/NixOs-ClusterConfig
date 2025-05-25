{
  inputs = {

    # Import nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    # HomeManager to overwrite the version used in cluster-config
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Import clusterConfig flake
    # Change this import to the github url
    clusterConfigFlake = {
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      # url = "github:Skasselbard/NixOs-ClusterConfig";
      url = "path:../../";
    };

    # Import disko to configure partitioning
    # If you want to use disko for formatting or device definitions, this option is required
    disko = {
      url = "github:nix-community/disko/v1.1.0";
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

    let # Definitions and imports

      system = "x86_64-linux";

      # import the nixpkgs attribute from the flake inputs
      pkgs = import nixpkgs { inherit system; };

      # The filters are used to resolve hosts when expanding the ClusterConfig
      filters = clusterConfigFlake.lib.filters;

      # Configuration from other Layers, e.g.: NixOs machine configurations
      configurations = (import "${self}/../00-exampleConfigs/") { inherit pkgs; };
      secrets = configurations.secrets;
      machines = configurations.machines;
      homeModules = configurations.homeModules;

      #####################################################
      # ClusterConfig
      #####################################################
      clusterConfig = clusterConfigFlake.lib.buildCluster {

        modules = [
          clusterConfigFlake.clusterConfigModules.default
          clusterConfigFlake.clusterConfigModules.secret-service
          clusterConfigFlake.clusterConfigModules.kubernetes
        ];

        domain = {
          suffix = "com";

          clusters = {

            # the cluster name will also be used for fqdn generation
            example = {

              #############################################
              # Services
              services = {

                # Static DNS via /etc/hosts file
                dns = {
                  roles.hosts = [ filters.clusterMachines ];
                  selectors = [ filters.clusterMachines ];
                  definition = clusterConfigFlake.clusterServices.staticDns;
                };

                secrets = {
                  selectors = [ filters.clusterMachines ];
                  definition = clusterConfigFlake.clusterServices.secret-service;
                };

                kubernetes = {

                  roles = {
                    controlPlane = [ filters.clusterMachines ];
                    worker = [ ];
                  };

                  selectors = [ filters.clusterMachines ];
                  definition = clusterConfigFlake.clusterServices.kubernetes;

                  extraConfig = {
                    services.kubernetes.cluster = {

                      # Used to self sign tls certificates for https communication
                      certificates = {
                        organizationUnit = "Demonstrations";
                        organization = "ExampleOrg";
                        country = "DE";
                        locality = "TownStadt";
                        province = "Bundesland";
                      };

                    };

                  };
                };

              };

              ############################################
              # Users
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
                  homeManagerModules = [
                    homeModules.default
                    homeModules.starship
                  ];
                  systemConfig = {
                    isNormalUser = true;
                    extraGroups = [ "wheel" ];
                    # 'admin'
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
                  nixosModules = [
                    machines.vm0
                    # since the vms use disko for mounting, we still need to include the NixOs module
                    inputs.disko.nixosModules.default
                    (
                      { config, ... }:
                      {
                        users.users.etcd = {
                          secrets.file = with config.services.kubernetes.cluster.certificates; {
                            ca-cert = {
                              backendPath = "./etcd-ca.crt";
                              linkPath = etcd.caCertFile.sourcePath;
                            };
                            ca-key = {
                              backendPath = "./etcd-ca.key";
                              linkPath = etcd.caKeyFile.sourcePath;
                            };
                            server-cert = {
                              backendPath = "./etcd-server.crt";
                              linkPath = etcd.serverCertFile.sourcePath;
                            };
                            server-key = {
                              backendPath = "./etcd-server.key";
                              linkPath = etcd.serverKeyFile.sourcePath;
                            };
                            peer-cert = {
                              backendPath = "./etcd-peer.crt";
                              linkPath = etcd.peerCertFile.sourcePath;
                            };
                            peer-key = {
                              backendPath = "./etcd-peer.key";
                              linkPath = etcd.peerKeyFile.sourcePath;
                            };
                          };
                        };
                      }
                    )
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
                  ];
                };

              };
            };

          };

        };
      };

    in
    # DO NOT FORGET!
    clusterConfig; # use the generated cluster config as the flake content
}
