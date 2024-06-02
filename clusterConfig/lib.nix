{ lib, nixpkgs }:
with lib;
with lib.types;
let
  # imports 
  filters = import ./filters.nix { inherit lib; };

  #############
  # Type stubs that can be extended

  domainType = { clusterType ? { options = { }; } }:

    {
      clusters = mkOption { type = attrsOf (submodule clusterType); };
    };

  # If you extend the cluster user type, you also need to extent the machine user type
  clusterType = { userType ? { options = { }; }
    , clusterServiceType ? { options = { }; }, machineType ? { options = { }; }
    }:

    {
      options = {
        users = mkOption { type = attrsOf (submodule userType); };
        services = mkOption { type = attrsOf (submodule clusterServiceType); };
        machines = mkOption { type = attrsOf (submodule machineType); };
      };
    };

  # If you extend the machine user type, you also need to extent the cluster user type
  machineType =
    { userType ? { options = { }; }, virtualizationType ? { options = { }; } }:

    {
      options = {
        users = mkOption { type = attrsOf (submodule userType); };

        virtualization =
          mkOption { type = attrsOf (submodule virtualizationType); };

      };
    };

  ############
  # helper functions

  forEachAttrIn = attrSet: function: (attrsets.mapAttrs function attrSet);

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
      extensions = config.extensions;
    };

    # Evaluates the 'nixosModules' for each machine and adds the resulting nixosConfiguration to the machine config.
    nixosConfigurations = config: withServices:
      add.machineConfiguration config (clusterName: machineName: machineConfig:
        let

          serviceFreeConfig =
            nixpkgs.lib.nixosSystem { modules = machineConfig.nixosModules; };

          serviceContainingConfig = attrsets.foldlAttrs
            (acc: serviceName: serviceDefinition:
              let
                selectors = (filters.resolve
                  (toConfigAttrPaths serviceDefinition.selectors clusterName
                    config) config);
                roles = (forEachAttrIn serviceDefinition.roles (roleName: role:
                  (filters.resolve (toConfigAttrPaths role clusterName config)
                    config)));
              in acc.extendModules {
                modules = [
                  serviceDefinition.extraConfig
                  (serviceDefinition.definition {
                    inherit selectors roles;
                    this = machineConfig.annotations;
                  })
                ];
              }) serviceFreeConfig machineConfig.services;
        in {
          nixosConfiguration =
            if withServices then serviceContainingConfig else serviceFreeConfig;
        });

    # Adds a NixosModule build by 'moduleConfigFn' to each machine.
    # The moduleConfigFn builds a nixos module from three input parameters (clusterName, machineName, machineConfig).
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

  toConfigAttrPaths = filters: clusterName: config:
    lists.flatten (lists.forEach filters (filter: (filter clusterName config)));

  get = {

    # # returns a list with (unnamed) service Definitions from all services in the cluster
    # # and resolves the filter in roles and selectors
    # services = config:
    #   attrsets.attrValues ( # to list
    #     attrsets.mergeAttrsList (attrsets.attrValues ( # remove cluster names
    #       forEachAttrIn config.domain.clusters (clusterName: clusterConfig:
    #         (forEachAttrIn clusterConfig.services
    #           (serviceName: serviceDefinition: {
    #             "config" = serviceDefinition.config;
    #             selectors =
    #               (filters.toConfigAttrPaths serviceDefinition.selectors
    #                 clusterName config);
    #             roles = (forEachAttrIn serviceDefinition.roles (rolename: role:
    #               filters.toConfigAttrPaths role clusterName config));
    #           }))))));

    # Returns a set of machines.
    # Each machine is defined by a key value pair of machineName = machineConfig; in the set.
    machines = config:
      attrsets.mergeAttrsList (lists.flatten (attrsets.attrValues
        (forEachAttrIn config.domain.clusters
          (clusterName: clusterValue: clusterValue.machines))));
  };
in { inherit add get domainType clusterType machineType forEachAttrIn; }
