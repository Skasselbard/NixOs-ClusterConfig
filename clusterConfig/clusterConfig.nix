{ nixpkgs, nixos-generators }:
let
  pkgs = import nixpkgs {
    # the exact value of 'system' should be unimportant since we only use lib
    system = "x86_64-linux";
  };
in with pkgs.lib;
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

    # returns a list with (unnamed) service Definitions from all services in the cluster config
    # config -> {{ [path], serviceConfig}, ...}
    services = config:
      attrsets.attrValues ( # to list
        attrsets.mergeAttrsList (attrsets.attrValues ( # remove cluster names
          forEachAttrIn config.domain.clusters (clusterName: clusterConfig:
            (forEachAttrIn clusterConfig.services
              (serviceName: serviceDefinition: {
                "config" = serviceDefinition.config;
                selectors =
                  (filters.toConfigAttrPaths serviceDefinition.selectors
                    clusterName config);
                roles = (forEachAttrIn serviceDefinition.roles (rolename: role:
                  filters.toConfigAttrPaths role clusterName config));
              }))))));
  };

  add = {

    # clusterconfig -> ((clusterName -> machineName -> machineConfig) -> machineConfigAttr) -> clusterconfig
    machineConfiguration = config: machineConfigFn: {
      domain = attrsets.recursiveUpdate config.domain {
        clusters = (forEachAttrIn config.domain.clusters
          (clusterName: clusterConfig: {
            machines = forEachAttrIn clusterConfig.machines
              (machineName: machineConfig:
                (machineConfigFn clusterName machineName machineConfig));
          }));
      };
    };

    # clusterconfig -> configPath -> ((clusterName -> machineName -> machineConfig) -> machineConfigAttr) -> clusterconfig
    filteredMachineConfiguration = with builtins;
      config: filter: machineConfigFn:
      let attrPath = strings.splitString "." filter;
      in {
        domain = attrsets.recursiveUpdate config.domain {
          clusters = config.domain.clusters (forEachAttrIn
            (attrsets.filterAttrs (n: v: n == (head (tail (attrPath))))
              config.domain.clusters)
            # apply config function on filtered clusters
            (clusterName: clusterConfig: {
              machines = forEachAttrIn (attrsets.filterAttrs
                (n: v: n == (head (tail ((tail (attrPath))))))
                clusterConfig.machines) (machineName: machineConfig:
                  # apply config function on filtered machines
                  (machineConfigFn clusterName machineName machineConfig));
            }));
        };
      };

    nixosConfigurations = config:
      add.machineConfiguration config
      (clusterName: machineName: machineConfig: {
        nixosConfiguration =
          nixpkgs.lib.nixosSystem { modules = machineConfig.nixosModules; };
      });

    # clusterconfig -> ((clusterName -> machineName -> machineConfig) -> moduleAttr) -> clusterconfig
    nixosModule = config: moduleConfigFn:
      let
        domainAttr = config.domain;
        clusters = config.domain.clusters;
      in add.machineConfiguration config
      (clusterName: machineName: machineConfig: {
        nixosModules = (lists.flatten
          [ (moduleConfigFn clusterName machineName machineConfig) ])
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

    bootImageNixosConfiguration = machineConfig: {
      system = machineConfig.system;
      modules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        ({
          networking.interfaces = forEachAttrIn
            machineConfig.nixosConfiguration.config.networking.interfaces
            (interfaceName: interfaceDefinition:
              attrsets.getAttrs [ "useDHCP" "ipv4" "ipv6" ]
              interfaceDefinition);
          users.users =
            # filter some users that get created by default
            attrsets.filterAttrs (userName: userDefinition:
              ((strings.hasPrefix "nix" userName)
                || (strings.hasPrefix "systemd" userName) || userName
                == "backup" || userName == "messagebus" || userName == "nobody"
                || userName == "sshd"))
            machineConfig.nixosConfiguration.config.users;
        })
      ];
    };
  };

  filters = {

    hostname = hostName: clusterName: config:
      [ "domain.clusters.${clusterName}.machines.${hostName}" ];

    toConfigAttrPaths = filters: clusterName: config:
      lists.flatten
      (lists.forEach filters (filter: (filter clusterName config)));

    resolve = paths: config:
      lists.flatten (lists.forEach paths (path:
        let
          resolvedElement = (attrsets.attrByPath (strings.splitString "." path)
            {
              # this is the default element if the path was noct found
              # TODO: throw an error if the path cannot be founs?
            } config);
        in resolvedElement.annotations));
  };

  evalCluster = clusterConfig:
    evalModules {
      modules = [
        (import ./options.nix { lib = pkgs.lib; })
        { config = { domain = clusterConfig.domain; }; }
      ];
    };

  clusterAnnotation = config:
    add.nixosModule config (clusterName: machineName: machineConfig: ({
      networking.hostName = machineName;
      networking.domain = clusterName + "." + config.domain.suffix;
      nixpkgs.hostPlatform = mkDefault machineConfig.system;
    }));

  evalMachines = config: add.nixosConfigurations config;

  machineAnnotation = config:
    add.machineConfiguration config (clusterName: machineName: machineConfig: {
      annotations = {
        inherit clusterName machineName;
        ips = get.ips machineConfig.nixosConfiguration;
        fqdn = machineConfig.nixosConfiguration.config.networking.fqdn;
        # TODO: subnets?
      };
    });

  serviceAnnotation = with lists;
    config:
    let services = get.services config;
    in add.nixosModule config (clusterName: machineName: machineConfig:
      let
        # filter the service list for the ones that match the path of the current machine
        filteredServices = builtins.filter (service:
          (lists.any (filter:
            assert asserts.assertMsg (strings.hasPrefix "domain" filter)
              "Filter '${filter}' does not start with 'domain'. Filters need to be a path in the clusterConfig in the form like 'domain.clusterName.machineName'";
            filter == "domain.clusters.${clusterName}.machines.${machineName}")
            service.selectors)) services;
        # attrsets.mergeAttrsList # merge all matching services together
      in (lists.forEach filteredServices (service:
        # get the config closure and compute its result to form a complete NixosModule
        (service.config {
          selectors = debug.traceSeqN 8 service.selectors
            (filters.resolve service.selectors config);
          roles = service.roles;
          this = machineConfig.annotations; # machineConfig;
        }))));

  deploymentAnnotation = config:
    add.machineConfiguration config (clusterName: machineName: machineConfig: {
      stage0Iso = nixos-generators.nixosGenerate
        ((build.bootImageNixosConfiguration machineConfig) // {
          format = "iso";
        });
    });

in {

  inherit filters;

  # TODOs:
  # - conditionally include virtual interfaces (networking.interfaces.<name>.virtual = true) -> not useful for dns
  # - include dhcp hints for static dhcp ip -> known dhcp ips should be addable
  # tagging
  # - cluster annotations: fqdn, all ips, all machine names + fqdns, all service names, service selectors per service

  # a function that builds and evaluates the clusterconfig to apply directly on the cluster definition
  buildCluster = config:
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
      machineEvaluatedCluster = evalMachines clusterAnnotatedCluster;

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
      nixosConfiguredCluster = evalMachines serviceAnnotatedCluster;

      # Step 7:
      # Build the deployment scripts 
      deploymentAnnotatedCluster = deploymentAnnotation nixosConfiguredCluster;
    in deploymentAnnotatedCluster;

}
