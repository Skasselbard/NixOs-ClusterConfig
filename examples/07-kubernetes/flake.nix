{
  inputs = {

    # Import nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # HomeManager to overwrite the version used in cluster-config
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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

      # With the lib, we can evaluate the Cluster Config to access data from machines and services
      clusterLib = clusterConfigFlake.lib;
      # The filters are used to resolve hosts when expanding the ClusterConfig
      filters = clusterLib.filters;

      # Configuration from other Layers, e.g.: NixOs machine configurations
      configurations = (import ../00-exampleConfigs) { inherit pkgs; };
      secrets = configurations.secrets;
      machines = configurations.machines;
      homeModules = configurations.homeModules;

      # Kubernetes requires a lot of secrets and certificates
      # For this example we define them in a function in a separate file
      # See the certificate definitions for more details
      generateSecrets = import ./secrets.nix;

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

          clusterConfigFlake.clusterConfigModules.simple-dns
          # A module that defines scripts to generate tls certificates from a well defined data structure
          clusterConfigFlake.clusterConfigModules.certificates
        ];

        domain = {
          suffix = "com";

          clusters = {

            # the cluster name will also be used for fqdn generation
            example = {

              # Kubernetes has a lot of components running with different accounts on multiple machines.
              # For secure communication between these components, a lot of tls certificates are required.
              # The kubernetes service module defines a data structure for accounts including required rights.
              # The idea of the certificate generation is to transform these accounts into certificate definitions.
              # The certificates module can then generate the required certificates based on these definitions.
              certificates.sets =
                let
                  # We use the result of our clusterConfig build function to access the account definitions from the kubernetes service
                  kubernetesAccounts = clusterConfig.domain.clusters.example.services.kubernetes.accounts;
                  clusterName = "example.com";
                  # A function that takes a set of accounts and transforms them into certificate definitions with independent certificate authorities.
                  # In kubernetes we have two main sets of accounts: etcd and kubernetes.
                  mapSet = setName: {
                    # Certificate authorities definitions
                    ca = {
                      commonName = "${setName}-root-ca";
                      expires = "10 year";
                    };
                    # You can define intermediate certificate authorities with a signer
                    intermediates = {
                      "${setName}-ca" = {
                        commonName = "A";
                        domains = [ clusterName ];
                        expires = "5 year";
                        signedBy = [ "${setName}" ];
                      };
                    };
                    # The actual certificate definition.
                    # The main mapping from account to certificates happens here.
                    certs = builtins.mapAttrs (accountName: account: {
                      commonName = account.roleName or null;
                      organization = account.kubernetesGroup or null;
                      domains = account.domains or [ ];
                      ips = account.ips or [ ];
                      uri = [ ];
                      expires = "2 year";
                      # signedBy = [ "${setName}" ];
                      signedBy = [ "${setName}-ca" ];
                    }) kubernetesAccounts."${setName}";
                  };
                in
                {
                  # Apply the function to both accounts
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
                # The service defines scripts to deploy the secrets.
                # The secrets themselves are defined in the machine config below.
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

                  kubeConfigs = {
                    # We want to generate kubeConfigs for the admin and super-admin accounts
                    accountNames = [
                      "admin"
                      "super-admin"
                    ];
                    # The api server address used in the kube-config files
                    apiServer = "192.168.122.210";
                    # We used the intermediate cas to sign our certificates, so we need them to generate valid kube-configs as well
                    caPath = "./certificates/kubernetes/intermediates/kubernetes-ca.crt";
                  };

                  # nodes to which the service is copied to
                  selectors = [ filters.clusterMachines ];

                  # This will configure keepalived to setup a ha endpoint for the cluster
                  # The keepalived master server will assume this address, but when it is unreachable, a backup server will fail over.
                  virtualIps = [ "192.168.122.210" ];

                  # You can add extra configuration to the kubernetes service module here
                  # In theory you could e.g. overwrite and disable high-availability services (keepalived and ha proxy) here if you don't need them, however, this is untested.
                  extraConfig =
                    {
                      pkgs,
                      config,
                      lib,
                      ...
                    }:
                    {
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

                vm0 =
                  let
                    machineName = "vm0";
                  in
                  {
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
                      "cluster.example.com/TestLabel" = machineName;
                    };

                    deployment = {
                      targetHost = "192.168.122.200";
                      formatScript = "disko"; # format vms on recreation
                    };

                    # Call the function to generate and define the secrets for this machine
                    # You can deploy secrets and certificates in other ways as well.
                    # In fact the secret service module is a proof of concept and that probably shows.
                    # If you decide to use another method, you can reuse the account definitions from the kubernetes service to generate and deploy the required certificates.
                    secrets = generateSecrets {
                      machineConfig = self.nixosConfigurations.${machineName}.config;
                      lib = pkgs.lib;
                    };

                    nixosModules = [
                      machines.vm0
                      # since the vms use disko for mounting, we still need to include the NixOs module
                      inputs.disko.nixosModules.default
                    ];
                  };

                vm1 =
                  let
                    machineName = "vm1";
                  in
                  {
                    inherit system;

                    kubernetes.nodeLabels = {
                      "cluster.example.com/TestLabel" = "vm1";
                    };
                    kubernetes.keepalived = {
                      virtualIpInterface = "eth0";
                      # priority = 234;
                    };

                    deployment = {
                      targetHost = "192.168.122.201";
                      formatScript = "disko"; # format vms on recreation
                    };

                    secrets = generateSecrets {
                      machineConfig = self.nixosConfigurations.${machineName}.config;
                      lib = pkgs.lib;
                    };

                    nixosModules = [
                      machines.vm1
                      inputs.disko.nixosModules.default
                    ];
                  };

                vm2 =
                  let
                    machineName = "vm2";
                  in
                  {
                    inherit system;

                    kubernetes.keepalived = {
                      virtualIpInterface = "eth0";
                    };

                    deployment = {
                      targetHost = "192.168.122.202";
                      formatScript = "disko"; # format vms on recreation
                    };

                    secrets = generateSecrets {
                      machineConfig = self.nixosConfigurations.${machineName}.config;
                      lib = pkgs.lib;
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
