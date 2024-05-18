{ lib, nixpkgs }:
with lib;
with lib.types;
let
  # imports 
  filters = import ./filters.nix { inherit lib; };

  #############
  # Type stubs that can be extended

  domainType = { clusterType ? { options = { }; } }: {
    clusters = mkOption { type = attrsOf (submodule clusterType); };
  };

  clusterType = { # -
    userType ? { options = { }; }, # -
    clusterServiceType ? { options = { }; }, # -
    machineType ? { options = { }; } }: {
      options = {
        users = mkOption { type = attrsOf (submodule userType); };
        services = mkOption { type = attrsOf (submodule clusterServiceType); };
        machines = mkOption { type = attrsOf (submodule machineType); };
      };
    };

  machineType = { # -
    userType ? { options = { }; }, # -
    virtualizationType ? { options = { }; } }: {
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

  get = {

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

    machines = config:
      attrsets.mergeAttrsList (lists.flatten (attrsets.attrValues
        (forEachAttrIn config.domain.clusters
          (clusterName: clusterValue: clusterValue.machines))));
  };
in { inherit add get domainType clusterType machineType forEachAttrIn; }
