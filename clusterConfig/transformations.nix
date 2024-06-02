{ pkgs, nixos-generators, clusterlib, ... }:
with pkgs.lib;
let # imports
  filters = import ./filters.nix {
    inherit clusterlib;
    lib = pkgs.lib;
  };

  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;
  get = clusterlib.get;

  # get the config closure and compute its result to form a complete NixosModule
  reduceService = machineConfig: service: config:
    (service.config {
      selectors = (filters.resolve service.selectors config);
      roles = forEachAttrIn service.roles
        (name: filter: filters.resolve filter config);
      this = machineConfig.annotations; # machineConfig;
    });

  # assert filter properties and assemble error message
  filterFormatIsOk = filter:
    asserts.assertMsg (strings.hasPrefix "domain" filter)
    "Filter '${filter}' does not start with 'domain'. Filters need to be a path in the clusterConfig in the form like 'domain.clusterName.machineName'";

  toConfigAttrPaths = filters: clusterName: config:
    lists.flatten (lists.forEach filters (filter: (filter clusterName config)));

in let

  # Add NixOs modules inferred by the cluster config to each Machines NixOs modules
  # This includes:
  # - Hostnames: networking.hostname is set to the name of the machiene definition
  # - DomainName: networkinig.domain is set to clusterName.domainSuffix
  # - Hostplattform: pkgs.hostPlattform is set to the configured system in the machine configuration
  # - UserDefinitions: users.users is set with information from cluster-users and machine-users
  clusterAnnotation = config:

    add.nixosModule config (clusterName: machineName: machineConfig:
      let

        clusterUsers = config.domain.clusters."${clusterName}".users;
        machineUsers = machineConfig.users;

      in [

        { # machine config
          networking.hostName = machineName;
          networking.domain = clusterName + "." + config.domain.suffix;
          nixpkgs.hostPlatform = mkDefault machineConfig.system;
        }

        # make different modules for cluster and user definitions so that the NixOs
        # module system handles the merging

        { # cluster users
          users.users =
            forEachAttrIn clusterUsers (n: userConfig: userConfig.systemConfig);
          # forEach user (homeManagerModules ++ userHMModules) -> if not empty -> enable HM
        }

        { # machine users
          users.users =
            forEachAttrIn machineUsers (n: userConfig: userConfig.systemConfig);
        }

      ]);

  # Add the service configurations to the modlues of the tergeted machines
  # A service is a set that defines selectors, roles and a config function that defines a proto nixosModule.
  # 
  # A selector is a list of filters define the hosts on which the service should be deployed.
  #
  # The roles attribute defines a set of key value pairs where the key is a role name and the value is a list of filters.
  #
  # A filter is a function that takes a clusterName and a config and returns a list of paths in the clusterConfig.
  # You can look in the 'filters.nix' module to find examples like a filter that returns a path to a host when it is resolved.
  # Filters for selectors should always point to a machine configuration.
  #
  # The proto module has one of the following forms:
  #
  #  {selectors, roles, this }: {
  #     ... # nixosConfig
  #  };
  #
  # or
  #
  #  {selectors, roles, this }: 
  #     { config, pkgs, ...}:
  #     ... # nixosConfig
  #  };
  #
  # The proto modules wil get resolved to a final nixosModule by this function by applying the first
  # input closure (i.e. '{selectors, roles, this }:').
  # The values for the clousre are #TODO:
  # 
  # As a result, the service can use cluster and machine information in its definition.
  serviceAnnotation = with lists;
    config:
    add.nixosModule config (clusterName: machineName: machineConfig:
      let

        services = attrsets.attrValues
          (forEachAttrIn config.domain.clusters."${clusterName}".services
            (serviceName: serviceDefinition: {
              "config" = serviceDefinition.config;
              selectors =
                (toConfigAttrPaths serviceDefinition.selectors clusterName
                  config);
              roles = (forEachAttrIn serviceDefinition.roles
                (rolename: role: toConfigAttrPaths role clusterName config));
            }));

        # filter the service list for the ones that match the path of the current machine
        filteredServices = builtins.filter (service:
          (lists.any (filter:
            assert filterFormatIsOk filter;
            filter == "domain.clusters.${clusterName}.machines.${machineName}")
            service.selectors)) services;

      in lists.forEach filteredServices (service:
        # get the config closure and compute its result to form a complete NixosModule
        reduceService machineConfig service config));

in {

  config.extensions = {
    clusterTransformations = [ clusterAnnotation ];
    # moduleTransformations = [ serviceAnnotation ];
  };

}
