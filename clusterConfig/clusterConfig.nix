{ pkgs }:
with pkgs.lib;
let

  get = {
    attrName = attr: (head (builtins.attrNames attr));

    interface = {
      ips = interfaceDefinition:
        let
          v4Adresses = lists.forEach interfaceDefinition.ipv4.addresses
            (addressDefinition: addressDefinition.address);
          v6Adresses = lists.forEach interfaceDefinition.ipv6.addresses
            (addressDefinition: addressDefinition.address);
        in lists.flatten [ v4Adresses v6Adresses ];

      definitions = machineConfig:
        lists.forEach (get.interface.names machineConfig) (interfaceName: {
          "${interfaceName}" = builtins.removeAttrs
            (builtins.getAttr interfaceName
              machineConfig.config.networking.interfaces) [ "subnetMask" ];
        });

      names = machineConfig:
        attrsets.attrNames machineConfig.config.networking.interfaces;
    };

    host = selector: clusterConfig:
      {
        # TODO: return machineConfig
      };

    ips = machineConfig:
      let
        interfaces = attrsets.mergeAttrsList
          (lists.forEach (get.interface.definitions machineConfig) (interface:
            let
              interfaceName = (head (attrsets.attrNames interface));
              interfaceValue = (head (attrsets.attrValues interface));
            in { "${interfaceName}" = get.interface.ips interfaceValue; }));
      in {
        all = lists.flatten (attrsets.attrValues interfaces);
      } // interfaces;

    Services.Selectors = cluster: cluster.services;
    machines = cluster: cluster.machines;
    clusters = config.domain.clusters;
  };

  add = {

    # clusterconfig -> ((clusterName -> machineName -> machineConfig) -> machineConfigAttr) -> clusterconfig
    machineConfiguration = config: machineConfigFn:
      let
        domainAttr = config.domain;
        clusters = config.domain.clusters;
      in {
        domain = domainAttr // {
          clusters = (attrsets.mapAttrs (clusterName: clusterConfig:
            (clusterConfig // {
              machines = attrsets.mapAttrs (machineName: machineConfig:
                machineConfig
                // (machineConfigFn clusterName machineName machineConfig))
                clusterConfig.machines;
            })) clusters);
        };
      };

    nixosConfigurations = nixpkgs: config:
      add.machineConfiguration config
      (clusterName: machineName: machineConfig: {
        nixosConfiguration =
          nixpkgs.lib.nixosSystem { modules = machineConfig.nixosModules; };
      });

    # clusterconfig -> ((clusterName -> machineName -> machineConfig) -> moduleAttr) -> clusterconfig
    nixosModule = config: moduleConfig:
      let
        domainAttr = config.domain;
        clusters = config.domain.clusters;
      in add.machineConfiguration config
      (clusterName: machineName: machineConfig: {
        nixosModules = [ (moduleConfig clusterName machineName machineConfig) ]
          ++ machineConfig.nixosModules;
      });

  };
  build = {
    # config -> {"machine1.cluster1.domainSuffix" = machine1Cluster1Definition; ... "machineN.clusterN.domainSuffix" = machineNClusterNDefinition;}
    # Reduces 'config.domain' to a set of named machineTypes.
    # The machine names are convertet to a domain name in the form of 'machineName.clusterName.domainSuffix'.
    machineSet = config: # root of a cluster configuration
      attrsets.mergeAttrsList (attrValues (attrsets.mapAttrs
        (clusterPath: clusterDefinition:
          (build.machinePaths clusterPath clusterDefinition))
        (build.clusterPaths config)));

    # config -> { "cluster1.domainSuffix" = cluster1Definition; ... "clusterN.domainSuffix" = clusterNDefinition}
    # Reduces 'config.domain' to a set of named clusterTypes.
    # The cluster names are convertet to a domain name in the form of 'clusterName.domainSuffix'.
    clusterPaths = config: # root of a cluster configuration
      attrsets.mapAttrs' (clusterName: clusterDefinition:
        nameValuePair (clusterName + "." + config.domain.suffix)
        clusterDefinition) config.domain.clusters;

    # clusterPath: clusterDefinition: -> {machine1DnsName = machine1Definition; ... machineNName = MachineNDefinition;}
    # Returns a set of named machines given a (cluster-) name and a clusterType.
    # The machine names are convertet to a domain name in the form of 'machineName.clusterName.domainSuffix'.
    machinePaths = clusterPath: clusterDefinition:
      attrsets.mapAttrs' (machineName: machineDefinition:
        nameValuePair (machineName + "." + clusterPath) machineDefinition)
      clusterDefinition.machines;
  };

  evalCluster = clusterConfig:
    pkgs.lib.evalModules {
      modules = [
        (import ./options.nix { inherit pkgs; })
        { config = { domain = clusterConfig.domain; }; }
      ];
    };

  clusterAnnotation = config:
    add.nixosModule config (clusterName: machineName: machineConfig: ({
      networking.hostName = machineName;
      networking.domain = clusterName + "." + config.domain.suffix;
      nixpkgs.hostPlatform = mkDefault machineConfig.system;
    }));

  evalMachines = nixpkgs: config: add.nixosConfigurations nixpkgs config;

  machineAnnotation = config:
    add.machineConfiguration config (clusterName: machineName: machineConfig: {
      ips = get.ips machineConfig.nixosConfiguration;
    });

  serviceAnnotation = config: config;
  deploymentAnnotation = config: config;

in {

  # TODOs:
  # conditionally include virtual interfaces (networking.interfaces.<name>.virtual = true) -> not useful for dns
  # include dhcp hints for static dhcp ip -> known dhcp ips should be addable
  # 
  # a function that builds and evaluates the clusterconfig to apply diractly on the cluster definition
  #   - add all attributes that can be directly inferred
  #   - evaluate the cluster
  #   - evaluate all machines and
  #   - add all necessary evaluation attributes (e.g. ips) to the cluster config
  #   - build a map of selector -> host
  #   - add all service configs to the machines

  buildCluster = nixpkgs: config:
    let
      # Step 1:
      # Evaluate the cluster to check for type conformity
      evaluatedCluster = (evalCluster config).config;

      # Step 2:
      # Annotate all machines with data from the cluster config.
      # This includes:
      # - Hostnames: networking.hostname is set to the name of the machiene definition
      # - DomainName: networkinig.domain is set to clusterName.domainSuffix
      # - Hostplattform: pkgs.hostPlattform is set to the configured system in the machine configuration
      clusterAnnotatedCluster = clusterAnnotation evaluatedCluster;

      # Step 3:
      # Evaluate the nixosModules from all machines to generate a first NixosConfiguration.
      # This config will be overwritten later.
      machineEvaluatedCluster = evalMachines nixpkgs clusterAnnotatedCluster;

      # Step 4:
      # Annotate the cluster with data from the machine configurations
      # This includes:
      # - the used IP addresses
      # - the FQDN
      evalAnnotatedCluser = machineAnnotation machineEvaluatedCluster;

      # Step 5:
      # Add the service configurations to the modlues of the tergeted machines
      serviceAnnotatedCluster = serviceAnnotation evalAnnotatedCluser;

      # Step 6:
      # Evaluate the final NixosConfigurations that can be added as build targets
      nixosConfiguredCluster = evalMachines nixpkgs serviceAnnotatedCluster;

      # Step 7:
      # Build the deployment scripts 
      deploymentAnnotatedCluster = deploymentAnnotation nixosConfiguredCluster;
    in deploymentAnnotatedCluster;

}
