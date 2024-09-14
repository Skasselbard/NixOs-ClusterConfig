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

    # Evaluates the 'nixosModules' for each machine and adds the resulting nixosConfiguration to the machine config.
    nixosConfigurations = config:
      update.machines config (clusterName: machineName: machineConfig: {
        nixosConfiguration =
          nixpkgs.lib.nixosSystem { modules = machineConfig.nixosModules; };
      });

    # Adds a NixosModule build by 'moduleConfigFn' to each machine.
    # The moduleConfigFn builds a nixos module from three input parameters (clusterName, machineName, machineConfig).
    # clusterconfig -> ((clusterName -> machineName -> machineConfig) -> moduleAttr) -> clusterconfig
    nixosModule = config: moduleConfigFn:
      let
        domainAttr = config.domain;
        clusters = config.domain.clusters;
      in update.machines config (clusterName: machineName: machineConfig: {
        nixosModules = (lists.flatten
          [ (moduleConfigFn clusterName machineName machineConfig) ])
          ++ machineConfig.nixosModules;
      });

  };

  get = {
    # Returns a set of machines.
    # Each machine is defined by a key value pair of machineName = machineConfig; in the set.
    machines = config:
      attrsets.mergeAttrsList (lists.flatten (attrsets.attrValues
        (forEachAttrIn config.domain.clusters
          (clusterName: clusterValue: clusterValue.machines))));
  };

  # change the attributes on a clusterConfig level, keep unmentiopned values
  update = {

    # updateClustersFn = clusterName -> clusterConfig -> clusterConfig
    clusters = config: updateClustersFn:
      config // {
        domain = config.domain // {
          clusters = (forEachAttrIn config.domain.clusters
            (clusterName: clusterConfig:
              clusterConfig // (updateClustersFn clusterName clusterConfig)));
        };
      };

    # updateServicesFn = clusterName -> serviceName -> serviceConfig -> serviceConfig
    services = config: updateServicesFn:
      update.clusters config (clusterName: clusterConfig: {
        services = (forEachAttrIn clusterConfig.services
          (serviceName: serviceConfig:
            serviceConfig
            // (updateServicesFn clusterName serviceName serviceConfig)));
      });

    # updateMachinesFn = clusterName -> machineName -> machineConfig -> machineConfig
    machines = config: updateMachinesFn:
      update.clusters config (clusterName: clusterConfig: {
        machines = (forEachAttrIn clusterConfig.machines
          (machineName: machineConfig:
            machineConfig
            // (updateMachinesFn clusterName machineName machineConfig)));
      });

    # updateUsersFn = clusterName -> serName -> userConfig -> userConfig
    users = config: updateUsersFn:
      update.clusters config (clusterName: clusterConfig: {
        users = (forEachAttrIn clusterConfig.users (userName: userConfig:
          userConfig // (updateUsersFn clusterName userName userConfig)));
      });
  };

  # overwrite the attributes on a clusterConfig level, delete unesed values
  overwrite = {

    # updateClustersFn = clusterName -> clusterConfig -> clusterConfig
    clusters = config: updateClustersFn:
      config // {
        domain = config.domain // {
          clusters = (forEachAttrIn config.domain.clusters
            (clusterName: clusterConfig:
              (updateClustersFn clusterName clusterConfig)));
        };
      };

    # updateServicesFn = clusterName -> serviceName -> serviceConfig -> serviceConfig
    services = config: updateServicesFn:
      update.clusters config (clusterName: clusterConfig: {
        services = (forEachAttrIn clusterConfig.services
          (serviceName: serviceConfig:
            (updateServicesFn clusterName serviceName serviceConfig)));
      });

    # updateMachinesFn = clusterName -> machineName -> machineConfig -> machineConfig
    machines = config: updateMachinesFn:
      update.clusters config (clusterName: clusterConfig: {
        machines = (forEachAttrIn clusterConfig.machines
          (machineName: machineConfig:
            (updateMachinesFn clusterName machineName machineConfig)));
      });

    # updateUsersFn = clusterName -> serName -> userConfig -> userConfig
    users = config: updateUsersFn:
      update.clusters config (clusterName: clusterConfig: {
        users = (forEachAttrIn clusterConfig.users (userName: userConfig:
          (updateUsersFn clusterName userName userConfig)));
      });
  };

  filterWhitelist = attrset: whitelist:
    forEachAttrIn attrset (name: value:
      let
        attrPaths = lists.forEach whitelist (strings.splitString ".");
        attrVals =
          lists.forEach attrPaths (path: attrsets.getAttrFromPath path value);
        attrsZpped = lists.zipLists attrPaths attrVals;
      in (lists.foldr (tuple: current:
        (attrsets.recursiveUpdate current
          (attrsets.setAttrByPath tuple.fst tuple.snd))) { } attrsZpped));

in {
  inherit add get domainType clusterType machineType forEachAttrIn update
    overwrite;
}
