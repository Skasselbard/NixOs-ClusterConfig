{
  inputs = {

    # Import nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # HomeManager to overwrite the version used in cluster-config
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
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

    let # Definitions and imports

      system = "x86_64-linux";

      # import the nixpkgs attribute from the flake inputs
      pkgs = import nixpkgs { inherit system; };

      # The filters are used to resolve hosts when expanding the ClusterConfig
      filters = clusterConfigFlake.lib.filters;

      # Configuration from other Layers, e.g.: NixOs machine configurations
      configurations = (import ../00-exampleConfigs) { inherit pkgs; };
      secrets = configurations.secrets;
      machines = configurations.machines;
      homeModules = configurations.homeModules;

      #####################################################
      # ClusterConfig
      #####################################################
      clusterConfig = clusterConfigFlake.lib.buildCluster {

        modules = [
          clusterConfigFlake.clusterConfigModules.default
          # The secret-service module is used to deploy secrets for this example
          # It gets the job done but in a production cluster you might want to use another solution or at least validate the security implications
          clusterConfigFlake.clusterConfigModules.secret-service
          # Add the kubernetes module
          # The module adds the certificate generation and makes flake dependencies available in the service config
          # It also defines annotations for keepalived virtualIps and kubernetes node labels
          clusterConfigFlake.clusterConfigModules.kubernetes

          # TODO: add to flake exports
          ../../src/services/dns/clusterModule.nix
          ../../src/modules/certificates/clusterModule.nix
        ];

        domain = {
          suffix = "com";

          clusters = {

            # the cluster name will also be used for fqdn generation
            example = {

              certificates.sets =
                let
                  kubernetesAccounts = clusterConfig.domain.clusters.example.services.kubernetes.accounts;
                  clusterName = "example.com";
                  mapSet = setName: {
                    ca = {
                      commonName = "${setName}-root-ca";
                      expires = "10 year";
                    };
                    intermediates = {
                      "${setName}-ca" = {
                        commonName = "A";
                        domains = [ clusterName ];
                        expires = "5 year";
                        signedBy = [ "${setName}" ];
                      };
                    };
                    certs = builtins.mapAttrs (accountName: account: {
                      commonName = account.roleName or null;
                      organization = account.kubernetesGroup or null;
                      domains = account.domains or [ ];
                      ips = account.ips or [ ];
                      uri = [ ];
                      expires = "2 year";
                      signedBy = [ "${setName}" ];
                      # signedBy = [ "${setName}-ca" ];
                    }) kubernetesAccounts."${setName}";
                  };
                in
                {
                  etcd = mapSet "etcd";
                  kubernetes = mapSet "kubernetes";
                };

              #############################################
              # Services
              services = {

                # Static DNS via /etc/hosts file
                dns = {
                  roles.hosts = [ filters.clusterMachines ];
                  selectors = [ filters.clusterMachines ];
                };

                # Secret service to make secrets and certificates for the kubernetes service users available on the machines
                secrets = {
                  selectors = [ filters.clusterMachines ];
                };

                # Kubernetes service; look closely, thats why you are here :D
                kubernetes = {

                  # In this example we define one dedicated control plane node (vm0), one mixed control plane + worker node (vm1) and one dedicated worker node (vm2)
                  roles = {
                    # these nodes run the control plane components and etcd
                    # you can define an etcd role separately if you want to run etcd on dedicated nodes.
                    # If no keepalived priority is defined in the machine annotations, the first node in the list will be the master for the virtual ip and the others will be backups in descending order.
                    controlPlane = [
                      (filters.hostname "vm0")
                      (filters.hostname "vm1")
                    ];
                    # These nodes run the workloads
                    worker = [
                      (filters.hostname "vm1")
                      (filters.hostname "vm2")
                    ];
                  };

                  # nodes to which the service is copied to
                  selectors = [ filters.clusterMachines ];

                  # This will configure keepalived to setup a ha endpoint for the cluster
                  # The keepalived master server will assume this address, but when it is unreachable, a backup server will fail over.
                  virtualIps = [ "192.168.122.210" ];

                  # You can add extra configuration to the kubernetes service module here
                  # In theory you could e.g. overwrite and disable high-availability services (keepalived and ha proxy) here if you don't ned them, however, this is not tested
                  # If you keep the high-availability services, make sure to adjust the virtualIps below
                  # The other configuration here is required to make the certificates work and to deploy them with the secret-service.
                  # If you bring and deploy your own certificates, you can skip that part.
                  extraConfig =
                    { config, lib, ... }:
                    let
                      machineName = config.networking.hostName;
                      isEtcdMember = config.services.etcd.enable;
                      isControlPlaneMember = config.services.kubernetes.apiserver.enable;
                      sources = config.clusterConfig.clusters.this.machines.this.kubernetes.certificates;
                    in
                    {
                      # configuring the secrets to deploy the certificates with the secret-service cluster service
                      users.users = {
                        etcd = lib.mkIf isEtcdMember {
                          secrets.file = {
                            ca-cert = {
                              backendPath = "./certificates/etcd/ca/etcd.crt";
                              # backendPath = "./certificates/etcd/intermediates/etcd-ca.crt";
                              linkPath = sources.etcd.caCertFile.sourcePath;
                              permissions = "555";
                            };
                            ca-key = {
                              backendPath = "./certificates/etcd/ca/etcd.key";
                              # backendPath = "./certificates/etcd/intermediates/etcd-ca.key";
                              linkPath = sources.etcd.caKeyFile.sourcePath;
                            };
                            server-cert = {
                              backendPath = "./certificates/etcd/certs/server.crt";
                              linkPath = sources.etcd.serverCertFile.sourcePath;
                              permissions = "444";
                            };
                            server-key = {
                              backendPath = "./certificates/etcd/certs/server.key";
                              linkPath = sources.etcd.serverKeyFile.sourcePath;
                            };
                            peer-cert = {
                              backendPath = "./certificates/etcd/certs/peer.crt";
                              linkPath = sources.etcd.peerCertFile.sourcePath;
                              permissions = "444";
                            };
                            peer-key = {
                              backendPath = "./certificates/etcd/certs/peer.key";
                              linkPath = sources.etcd.peerKeyFile.sourcePath;
                            };
                          };
                        };
                        kubernetes = {
                          secrets.file = {
                            apiserver-server-cert = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/kubernetes/certs/apiserver.crt";
                              linkPath = sources.apiServer.certFile.sourcePath;
                              permissions = "444";
                            };
                            apiserver-server-key = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/kubernetes/certs/apiserver.key";
                              linkPath = sources.apiServer.keyFile.sourcePath;
                            };
                            ca-cert = {
                              backendPath = "./certificates/kubernetes/ca/kubernetes.crt";
                              # backendPath = "./certificates/kubernetes/intermediates/kubernetes-ca.crt";
                              linkPath = sources.caCertFile.sourcePath;
                              permissions = "555";
                            };
                            ca-key = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/kubernetes/ca/kubernetes.key";
                              # backendPath = "./certificates/kubernetes/intermediates/kubernetes-ca.key";
                              linkPath = sources.caKeyFile.sourcePath;
                            };
                            "etcd-client-cert-${machineName}" = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/etcd/certs/apiserver-etcd-client-${machineName}.crt";
                              linkPath = sources.apiServer.etcdClientCertFile.sourcePath;
                              permissions = "444";
                            };
                            "etcd-client-key-${machineName}" = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/etcd/certs/apiserver-etcd-client-${machineName}.key";
                              linkPath = sources.apiServer.etcdClientKeyFile.sourcePath;
                            };
                            "kubelet-server-cert-${machineName}" = {
                              backendPath = "./certificates/kubernetes/certs/kubelet-${machineName}.crt";
                              linkPath = sources.kubeletCertFile.sourcePath;
                              permissions = "444";
                            };
                            "kubelet-server-key-${machineName}" = {
                              backendPath = "./certificates/kubernetes/certs/kubelet-${machineName}.key";
                              linkPath = sources.kubeletKeyFile.sourcePath;
                            };
                            "kubelet-client-cert-${machineName}" = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/kubernetes/certs/apiserver-kubelet-client-${machineName}.crt";
                              linkPath = sources.apiServer.kubeletClientCertFile.sourcePath;
                              permissions = "444";
                            };
                            "kubelet-client-key-${machineName}" = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/kubernetes/certs/apiserver-kubelet-client-${machineName}.key";
                              linkPath = sources.apiServer.kubeletClientKeyFile.sourcePath;
                            };
                            "addon-manager-cert-${machineName}" = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/kubernetes/certs/admin.crt";
                              linkPath = sources.addonManagerCertFile.sourcePath;
                              permissions = "444";
                            };
                            "addon-manager-key-${machineName}" = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/kubernetes/certs/admin.key";
                              linkPath = sources.addonManagerKeyFile.sourcePath;
                            };
                            "controller-manager-cert-${machineName}" = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/kubernetes/certs/controller-manager-${machineName}.crt";
                              linkPath = sources.controllerManagerCertFile.sourcePath;
                              permissions = "444";
                            };
                            "controller-manager-key-${machineName}" = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/kubernetes/certs/controller-manager-${machineName}.key";
                              linkPath = sources.controllerManagerKeyFile.sourcePath;
                            };
                            "scheduler-cert-${machineName}" = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/kubernetes/certs/scheduler-${machineName}.crt";
                              linkPath = sources.schedulerCertFile.sourcePath;
                              permissions = "444";
                            };
                            "scheduler-key-${machineName}" = lib.mkIf isControlPlaneMember {
                              backendPath = "./certificates/kubernetes/certs/scheduler-${machineName}.key";
                              linkPath = sources.schedulerKeyFile.sourcePath;
                            };
                            service-account = lib.mkIf isControlPlaneMember {
                              backendPath = "./certs/sa.pub";
                              linkPath = sources.saPubFile.sourcePath;
                              permissions = "444";
                            };
                            service-account-key = lib.mkIf isControlPlaneMember {
                              backendPath = "./certs/sa.key";
                              linkPath = sources.saKeyFile.sourcePath;
                            };
                          };
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

                  # The kubernetes cluster module defines some machine options to setup keepalived and kubernetes node labels
                  # Some of them are required to configure keepalived
                  kubernetes.keepalived = {
                    # Required to configure the interface for the virtual ip.
                    virtualIpInterface = "eth0";
                    # You can define the priority here, the higher the value, the higher the priority.
                    # Max value is 255.
                    # The machine with the highest priority will be the master for the virtual ip.
                    # If no priority is defined here, priorities will be assigned in order of the role definition beginning with 255; priorities that are already assigned for other nodes will be skipped.
                    # priority = 236;
                  };
                  # You can define labels for kubernetes nodes here.
                  # These labels will be added to the kubernetes node definition.
                  # You can list them with ``kubectl get nodes --show-labels``
                  kubernetes.nodeLabels = {
                    "cluster.example.com/LOCALTestLabel" = "vm0";
                  };

                  deployment = {
                    targetHost = "192.168.122.200";
                    formatScript = "disko"; # format vms on recreation
                  };

                  nixosModules = [
                    machines.vm0
                    # since the vms use disko for mounting, we still need to include the NixOs module
                    inputs.disko.nixosModules.default
                  ];
                };

                vm1 = {
                  inherit system;

                  kubernetes.nodeLabels = {
                    "cluster.example.com/LOCALTestLabel" = "vm1";
                  };
                  kubernetes.keepalived = {
                    virtualIpInterface = "eth0";
                    # priority = 234;
                  };

                  deployment = {
                    targetHost = "192.168.122.201";
                    formatScript = "disko"; # format vms on recreation
                  };

                  nixosModules = [
                    machines.vm1
                    inputs.disko.nixosModules.default
                  ];
                };

                vm2 = {
                  inherit system;

                  kubernetes.keepalived = {
                    virtualIpInterface = "eth0";
                  };

                  deployment = {
                    targetHost = "192.168.122.202";
                    formatScript = "disko"; # format vms on recreation
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
    ######################################
    # Final flake output
    ######################################
    # DO NOT FORGET!
    clusterConfig; # use the generated cluster config as the flake content
}
