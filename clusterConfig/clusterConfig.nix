{ pkgs }:
with pkgs.lib;
let
  forEachAttrIn = attrSet: function: (attrsets.mapAttrs function attrSet);

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

    # config -> {{ [path], serviceConfig}, ...}
    services = config:
      attrsets.attrValues ( # to list
        attrsets.mergeAttrsList (attrsets.attrValues ( # remove cluster names
          forEachAttrIn config.domain.clusters (clusterName: clusterConfig:
            (forEachAttrIn clusterConfig.services
              (serviceName: serviceDefinition: {
                filters = lists.flatten (lists.forEach serviceDefinition.filters
                  (filter: (filter clusterName)));
                "config" = serviceDefinition.config;
              }))))));
  };

  add = {

    # 
    services = config: services { };

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

    # clusterconfig -> configPath -> ((clusterName -> machineName -> machineConfig) -> machineConfigAttr) -> clusterconfig
    filteredMachineConfiguration = with builtins;
      config: filter: machineConfigFn:
      let
        attrPath = strings.splitString "." filter;
        domainAttr = config.domain;
        clusters = config.domain.clusters;
      in assert asserts.assertMsg ((head attrPath) == "domain")
        "Filter '${filter}' does not start with 'domain'. Filters need to be a path in the clusterConfig in the form like 'domain.clusterName.machineName'"; {
          domain = domainAttr // # -
            {
              clusters = clusters // # -
                (attrsets.mapAttrs (clusterName: clusterConfig:
                  # apply config function on filtered clusters
                  (clusterConfig // # -
                    {
                      machines = clusterConfig.machines // # -
                        attrsets.mapAttrs (machineName: machineConfig:
                          # apply config function on filtered machines
                          machineConfig
                          // (machineConfigFn clusterName machineName
                            machineConfig)) (attrsets.filterAttrs
                              (n: v: n == (head (tail ((tail (attrPath))))))
                              clusterConfig.machines);
                    }))
                  (attrsets.filterAttrs (n: v: n == (head (tail (attrPath))))
                    clusters));
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

  filters = {
    hostname = hostName: clusterName: [ "domain.${clusterName}.${hostName}" ];
    resolve = filter: config:
      lists.forEach filter ((path:
        attrsets.attrByPath (strings.splitString "." path) config).annotations);
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
      annotations = {
        ips = get.ips machineConfig.nixosConfiguration;
        config = machineConfig.nixosConfiguration.config;
        fqdn = machineConfig.nixosConfiguration.config.networking.fqdn;
        # TODO: subnets?
      };
    });

  serviceAnnotation = with lists;
    config:
    let
      services = get.services config;
      # service = config.domain.clusters.example.services.vault;
      # filter = builtins.head ((builtins.head service.filters) "example");
    in add.machineConfiguration config
    (clusterName: machineName: machineConfig: {
      annotations = let
        filteredServices = builtins.filter (service:
          (lists.any (filter: filter == "domain.${clusterName}.${machineName}")
            service.filters)) services;
      in machineConfig.annotations // {
        "services" = lists.forEach filteredServices (service: service.config);
      };
    })

    # (add.filteredMachineConfiguration config filter
    #   (clusterName: machineName: machineConfig:
    #     machineConfig // {
    #       annotations = machineConfig.annotations // {
    #         services = { };
    #         # machineConfig.annotations.services ++ [ service.config ];
    #       };
    #     }))

  ;

  deploymentAnnotation = config: config;

in {

  inherit filters;

  # TODOs:
  # conditionally include virtual interfaces (networking.interfaces.<name>.virtual = true) -> not useful for dns
  # include dhcp hints for static dhcp ip -> known dhcp ips should be addable
  # 
  # a function that builds and evaluates the clusterconfig to apply directly on the cluster definition
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
