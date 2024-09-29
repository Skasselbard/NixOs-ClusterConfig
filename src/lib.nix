{
  lib,
  nixpkgs,
  flake-utils,
}:
let
  # imports 
  filters = import ./filters.nix { inherit lib; };

  attrsets = lib.attrsets;
  lists = lib.lists;
  strings = lib.strings;

  mkOption = lib.mkOption;
  mkDefault = lib.mkDefault;
  attrsOf = lib.types.attrsOf;
  submodule = lib.types.submodule;

  ############
  # helper functions

  forEachAttrIn = attrSet: function: (attrsets.mapAttrs function attrSet);

  ip = {

    # only generate metaData with an empty config attribute
    tag =
      {
        role,
        address,
        port ? null, # don't define port if not set, so the service can define a default port
      }:
      {
        tag = if port == null then { inherit role address; } else { inherit role address port; };
        config = { };
      };

    # generate metadata and a config that 
    #   1. defines a single static address on the given interface
    #   2. opens the given port for UDP connections in the firewall
    staticIpV4OpenUdp =
      {
        role,
        address,
        port ? null, # don't define port if not set, so the service can define a default port
        subnetPrefixLength ? 24,
        interface,
      }:
      # TODO: assert address is an ipv4
      if port == null then
        {
          tag = {
            inherit role address;
          };

          config = {
            networking.interfaces."${interface}" = mkDefault {
              ipv4.addresses = [
                {
                  address = address;
                  prefixLength = subnetPrefixLength;
                }
              ];
            };
          };
        }
      else
        {
          tag = {
            inherit role address port;
          };

          config = {
            networking.firewall.allowedTCPPorts = [ port ];
            networking.interfaces."${interface}" = mkDefault {
              ipv4.addresses = [
                {
                  address = address;
                  prefixLength = subnetPrefixLength;
                }
              ];
            };
          };
        };

  };

  add = {

    # Evaluates the 'nixosModules' for each machine and adds the resulting nixosConfiguration to the machine config.
    nixosConfigurations =
      config:
      update.machines config (
        clusterName: machineName: machineConfig: {
          nixosConfiguration = nixpkgs.lib.nixosSystem { modules = machineConfig.nixosModules; };
        }
      );

    # Adds a NixosModule build by 'moduleConfigFn' to each machine.
    # The moduleConfigFn builds a nixos module from three input parameters (clusterName, machineName, machineConfig).
    # clusterconfig -> ((clusterName -> machineName -> machineConfig) -> moduleAttr) -> clusterconfig
    nixosModule =
      config: moduleConfigFn:
      update.machines config (
        clusterName: machineName: machineConfig: {
          nixosModules =
            (lists.flatten [ (moduleConfigFn clusterName machineName machineConfig) ])
            ++ machineConfig.nixosModules;
        }
      );

    # Add a package that can be build with `nix build #machineName.attrName` or run with `nix run #machineName.attrName`
    # updatePackageFn =  machineName -> machineConfig -> clusterconfig -> {attrName = derivation;}
    machinePackages =
      config: updatePackageFn:
      attrsets.recursiveUpdate config {

        packages =
          # The deployment options are generated for all system  configurations (by using flake utils)
          (flake-utils.lib.eachSystem flake-utils.lib.allSystems (system: {

            packages.machines = forEachAttrIn (get.machines config) (
              machineName: machineConfig: updatePackageFn machineName machineConfig config
            );

          })).packages;
      };

    # Add a package that can be build with `nix build #clusterName.attrName` or run with `nix run #clusterName.attrName`
    #
    # updatePackageFn =  clusterName -> clusterConfig -> {attrName = derivation;}
    # clusterConfig in this case means the config for the specific cluster (under domain.clusters.clusterName).
    clusterPackage =
      config: updatePackageFn:
      attrsets.recursiveUpdate config {
        packages =
          # The deployment options are generated for all system  configurations (by using flake utils)
          (flake-utils.lib.eachSystem flake-utils.lib.allSystems (system: {
            packages.cluster = forEachAttrIn (config.domain.clusters) (
              clusterName: clusterConfig: updatePackageFn clusterName clusterConfig
            );
          })).packages;
      };

  };

  eval = {

    # build the resulting nixos modules for a service definition
    service =
      config: clusterName: serviceDefinition: machineConfig:
      let
        selectors = (filters.resolve serviceDefinition.selectors clusterName config);

        roles = (
          forEachAttrIn serviceDefinition.roles (roleName: role: (filters.resolve role clusterName config))
        );

        clusterInfo = (get.clusterInfo config).domain.clusters."${clusterName}";

      in
      # build the nixOs module defined by the service
      [
        serviceDefinition.extraConfig

        # call the service definition with clusterInfo 
        (serviceDefinition.definition {
          inherit selectors roles clusterInfo;
          this = machineConfig.annotations;
        })

      ];
  };

  get = {
    # Returns the set of all machines for all clusters.
    # Each machine is defined by a key value pair of machineName = machineConfig; in the set.
    machines =
      config:
      attrsets.mergeAttrsList (
        lists.flatten (
          attrsets.attrValues (
            forEachAttrIn config.domain.clusters (clusterName: clusterValue: clusterValue.machines)
          )
        )
      );

    # Take a clusterConfig and return an essential representation that is serializable.
    # The essential representation is build by taking the annotation attributes of the clusterConfig nodes.
    clusterInfo =
      config:
      let

        machineInfo = overwrite.machines config (
          clusterName: machineName: machineConfig:
          machineConfig.annotations
          // {
            _type = "machine";
            deployment.tags = machineConfig.deployment.tags;
            deployment.targetHost = machineConfig.deployment.targetHost;
            deployment.targetPort = machineConfig.deployment.targetPort;
          }
        );

        serviceInfo = overwrite.services machineInfo (
          clusterName: serviceName: serviceConfig:
          serviceConfig.annotations // { _type = "service"; }
        );

        userInfo = update.clusters serviceInfo (
          clusterName: clusterConfig: { users = (attrsets.attrNames clusterConfig.users); }
        );
      in

      attrsets.recursiveUpdate config {
        # Generate a cluster config attribute that can be used to query config information
        # All leaves of the structure must be serializable; in particular: cannot be functions / lambdas
        clusterInfo.domain = userInfo.domain;
      };

  };

  # change the attributes on a clusterConfig level, keep unmentiopned values
  update = {

    # updateClustersFn = clusterName -> clusterConfig -> clusterConfig
    clusters =
      config: updateClustersFn:
      config
      // {
        domain = config.domain // {
          clusters = (
            forEachAttrIn config.domain.clusters (
              clusterName: clusterConfig: clusterConfig // (updateClustersFn clusterName clusterConfig)
            )
          );
        };
      };

    # updateServicesFn = clusterName -> serviceName -> serviceConfig -> serviceConfig
    services =
      config: updateServicesFn:
      update.clusters config (
        clusterName: clusterConfig: {
          services = (
            forEachAttrIn clusterConfig.services (
              serviceName: serviceConfig:
              serviceConfig // (updateServicesFn clusterName serviceName serviceConfig)
            )
          );
        }
      );

    # updateMachinesFn = clusterName -> machineName -> machineConfig -> machineConfig
    machines =
      config: updateMachinesFn:
      update.clusters config (
        clusterName: clusterConfig: {
          machines = (
            forEachAttrIn clusterConfig.machines (
              machineName: machineConfig:
              machineConfig // (updateMachinesFn clusterName machineName machineConfig)
            )
          );
        }
      );

    # updateUsersFn = clusterName -> serName -> userConfig -> userConfig
    users =
      config: updateUsersFn:
      update.clusters config (
        clusterName: clusterConfig: {
          users = (
            forEachAttrIn clusterConfig.users (
              userName: userConfig: userConfig // (updateUsersFn clusterName userName userConfig)
            )
          );
        }
      );
  };

  # overwrite the attributes on a clusterConfig level, delete unesed values
  overwrite = {

    # updateClustersFn = clusterName -> clusterConfig -> clusterConfig
    clusters =
      config: updateClustersFn:
      config
      // {
        domain = config.domain // {
          clusters = (
            forEachAttrIn config.domain.clusters (
              clusterName: clusterConfig: (updateClustersFn clusterName clusterConfig)
            )
          );
        };
      };

    # updateServicesFn = clusterName -> serviceName -> serviceConfig -> serviceConfig
    services =
      config: updateServicesFn:
      update.clusters config (
        clusterName: clusterConfig: {
          services = (
            forEachAttrIn clusterConfig.services (
              serviceName: serviceConfig: (updateServicesFn clusterName serviceName serviceConfig)
            )
          );
        }
      );

    # updateMachinesFn = clusterName -> machineName -> machineConfig -> machineConfig
    machines =
      config: updateMachinesFn:
      update.clusters config (
        clusterName: clusterConfig: {
          machines = (
            forEachAttrIn clusterConfig.machines (
              machineName: machineConfig: (updateMachinesFn clusterName machineName machineConfig)
            )
          );
        }
      );

    # updateUsersFn = clusterName -> serName -> userConfig -> userConfig
    users =
      config: updateUsersFn:
      update.clusters config (
        clusterName: clusterConfig: {
          users = (
            forEachAttrIn clusterConfig.users (
              userName: userConfig: (updateUsersFn clusterName userName userConfig)
            )
          );
        }
      );
  };

  filterWhitelist =
    attrset: whitelist:
    forEachAttrIn attrset (
      name: value:
      let
        attrPaths = lists.forEach whitelist (strings.splitString ".");
        attrVals = lists.forEach attrPaths (path: attrsets.getAttrFromPath path value);
        attrsZpped = lists.zipLists attrPaths attrVals;
      in
      (lists.foldr (
        tuple: current: (attrsets.recursiveUpdate current (attrsets.setAttrByPath tuple.fst tuple.snd))
      ) { } attrsZpped)
    );
  #############
  # Type stubs that can be extended

  domainType =
    {
      clusterType ? {
        options = { };
      },
    }:

    {
      clusters = mkOption { type = attrsOf (submodule clusterType); };
    };

  # If you extend the cluster user type, you also need to extent the machine user type
  clusterType =
    {
      userType ? {
        options = { };
      },
      clusterServiceType ? {
        options = { };
      },
      machineType ? {
        options = { };
      },
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
    {
      userType ? {
        options = { };
      },
      virtualizationType ? {
        options = { };
      },
    }:

    {
      options = {
        users = mkOption { type = attrsOf (submodule userType); };

        virtualization = mkOption { type = attrsOf (submodule virtualizationType); };

      };
    };

in
{
  inherit
    add
    clusterType
    domainType
    eval
    forEachAttrIn
    get
    ip
    machineType
    overwrite
    update
    ;
}
