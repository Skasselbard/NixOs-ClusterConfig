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

  outputs =
    inputs@{
      self,
      nixpkgs,
      clusterConfigFlake,
      ...
    }:

    let # Definitions and imports

      system = "x86_64-linux";

      # import the pkgs attribute from the flake inputs
      pkgs = import nixpkgs { inherit system; };

      # The filters are used to resolve hosts when expanding the ClusterConfig
      filters = clusterConfigFlake.lib.filters;
      clusterlib = clusterConfigFlake.lib;

      # Configuration from other Layers, e.g.: NixOs machine configurations
      configurations = (import "${self}/../00-exampleConfigs/") { inherit pkgs; };
      secrets = configurations.secrets;
      machines = configurations.machines;
      homeModules = configurations.homeModules;

      clusterConfig = clusterConfigFlake.lib.buildCluster {

        modules = with clusterConfigFlake.clusterConfigModules; [
          default
          vault
        ];

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
                  extraConfig = {
                    services.staticDns.customEntries = {
                      # You can set additional host entries, e.g. a default
                      # machine that points to vault
                      # This setting is not used by this example and only seves demonstration purposes
                      "vault.example.com" = "192.168.122.200";
                      "vault" = "192.168.122.200";
                    };
                  };
                };

                vault = {
                  roles = {
                    apiAddress = [ (filters.hostname "vm0") ];
                    clusterAddress = [ (filters.hostname "vm0") ];
                  };
                  selectors = [
                    (filters.hostname "vm0")
                    (filters.hostname "vm1")
                    (filters.hostname "vm2")
                  ];
                  definition = clusterConfigFlake.clusterServices.vault;
                  extraConfig = {
                    services.vault.cluster = {
                      enableUi = true;
                      # Used to self sign tls certificates for https communication
                      # By default written to /var/lib/vault/certs
                      certificates = {
                        organizationUnit = "Demonstrations";
                        organization = "ExampleOrg";
                        country = "DE";
                        locality = "TownStadt";
                        province = "Bundesland";
                      };
                    };

                    # Allow vault to be installed while other unfree packages are still blocked
                    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [ "vault-bin" ];
                  };
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

              machines =
                let
                  # All machines need certificates for TLS communication
                  # We deploy them with a function that takes a machine configuration
                  # and turns it into the deployment keys (as used by colmena or nixops).
                  vaultKeys =
                    machineConfig:
                    let
                      cfg = machineConfig.services.vault.cluster;
                      basePath = cfg.certificates.path.serverBase;
                      rootCertName = cfg.certificates.path.caRootCertName + ".crt";
                      tlsCertName = cfg.certificates.path.vaultCertName + ".crt";
                      tlsKeyName = cfg.certificates.path.vaultKeyName + ".key";
                    in
                    {

                      vaultRootCertFile = {
                        destDir = basePath;
                        name = rootCertName;
                        user = "vault";
                        keyFile = (basePath + rootCertName);
                        permissions = "0444";
                      };

                      vaultTlsCertFile = {
                        destDir = basePath;
                        name = tlsCertName;
                        user = "vault";
                        keyFile = (basePath + tlsCertName);
                        permissions = "0444";
                      };

                      vaultTlsCertKey = {
                        destDir = basePath;
                        name = tlsKeyName;
                        user = "vault";
                        keyCommand = [
                          "sudo"
                          "cat"
                          (basePath + tlsKeyName)
                        ];
                        permissions = "0440";
                      };

                    };
                in
                {

                  vm0 =
                    let
                      machineConfig = self.nixosConfigurations.vm0.config;
                      ip = "192.168.122.200";
                    in
                    {
                      inherit system;

                      serviceAddresses = [

                        (clusterlib.ip.tag {
                          role = "vault-listener";
                          address = ip;
                          port = 8200;
                        })

                        # ip.staticIpV4OpenUdp
                        # {
                        #   inherit ip;
                        #   role = "vault";
                        #   interface = "eth0";
                        # }

                      ];

                      deployment = {
                        targetHost = ip;
                        keys = vaultKeys machineConfig;
                        formatScript = "disko";
                      };

                      nixosModules = [
                        machines.vm0
                        # since the vms use disko for mounting, we still need to include the NixOs module
                        inputs.disko.nixosModules.default
                      ];

                    };

                  vm1 =
                    let
                      machineConfig = self.nixosConfigurations.vm1.config;
                      ip = "192.168.122.201";
                    in
                    {
                      inherit system;
                      deployment = {
                        targetHost = ip;
                        keys = vaultKeys machineConfig;
                        formatScript = "disko";
                      };
                      nixosModules = [
                        machines.vm1
                        inputs.disko.nixosModules.default
                      ];

                    };

                  vm2 =
                    let
                      machineConfig = self.nixosConfigurations.vm2.config;
                      ip = "192.168.122.202";
                    in
                    {
                      inherit system;
                      deployment = {
                        targetHost = ip;
                        keys = vaultKeys machineConfig;
                        formatScript = "disko";
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
