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

    # generate metaData and open tcp port
    openTcp =
      {
        role,
        address,
        port ? null, # don't define port if not set, so the service can define a default port
      }:
      {
        tag = if port == null then { inherit role address; } else { inherit role address port; };
        config.networking.firewall.allowedTCPPorts = [ port ];
      };

    # generate metadata and a config that
    #   1. defines a single static address on the given interface
    #   2. opens the given port for UDP connections in the firewall
    staticIpV4OpenTcp =
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

    # Add a package that can be build with `nix build #clusterName.machineName.package` or run with `nix run #clusterName.machineName.package`
    # updatePackageFn =  clusterName -> machineName -> {attrName = derivation;}
    machinePackages =
      config: updatePackageFn:
      attrsets.recursiveUpdate config {

        packages =
          # The deployment options are generated for all system  configurations (by using flake utils)
          (flake-utils.lib.eachSystem flake-utils.lib.allSystems (system: {

            packages = forEachAttrIn config.domain.clusters (
              clusterName: clusterDefinition:

              forEachAttrIn clusterDefinition.machines (
                machineName: _machineDefinition: updatePackageFn clusterName machineName
              )

            );

          })).packages;
      };

    # Add a package that can be build with `nix build #machines.machineName.services.attrName` or run with `nix run #machines.machineName.services.attrName`
    # updatePackageFn =  clusterName -> {attrName = derivation;}
    servicePackages =
      config: serviceName: updatePackageFn:
      attrsets.recursiveUpdate config {

        packages =
          # The deployment options are generated for all system  configurations (by using flake utils)
          (flake-utils.lib.eachSystem flake-utils.lib.allSystems (system: {

            packages = forEachAttrIn config.domain.clusters (
              clusterName: clusterDefinition:

              {
                "${serviceName}" = (updatePackageFn clusterName);
              }

            );

          })).packages;
      };

    # Add a package that can be build with `nix build #clusterName.attrName` or run with `nix run #clusterName.attrName`
    #
    # updatePackageFn =  clusterName -> {attrName = derivation;}
    # clusterConfig in this case means the config for the specific cluster (under domain.clusters.clusterName).
    clusterPackage =
      config: updatePackageFn:
      attrsets.recursiveUpdate config {
        packages =
          # The deployment options are generated for all system  configurations (by using flake utils)
          (flake-utils.lib.eachSystem flake-utils.lib.allSystems (system: {
            packages = forEachAttrIn config.domain.clusters (
              clusterName: _clusterDefinition: updatePackageFn clusterName
            );
          })).packages;
      };

  };

  eval = {

    # Building a representation of the cluster config.
    # This will be past to each nixos machine configuration, so that they can use the information for configuration, e.g. in cluster services.
    clusterConfig =
      config:
      {
        clusterName ? null, # if given, a "this" cluster is added that points to the cluster with the given name
        machineName ? null, # if given, a "this" machine is added that points to the machine with the given name in the "this" cluster
      }:
      if builtins.isString machineName && !builtins.isString clusterName then
        throw "trying to evaluate clusterConfig with machineName but no clusterName"
      else if !builtins.isString clusterName && clusterName != null then
        throw "trying to evaluate clusterConfig with clusterName that is not a string"
      else if !builtins.isString machineName && machineName != null then
        throw "trying to evaluate clusterConfig with machineName that is not a string"
      else
        let
          # Add cluster information including "this" pointer for the current cluster and machine.
          clusterConfigMachineResolved = attrsets.recursiveUpdate clusterConfigBase {
            clusters.this = attrsets.recursiveUpdate clusterConfigBase.clusters."${clusterName}" {
              machines.this = clusterConfigBase.clusters."${clusterName}".machines."${machineName}";
            };
          };

          clusterConfigClusterResolved = attrsets.recursiveUpdate clusterConfigBase {
            clusters.this = clusterConfigBase.clusters."${clusterName}";
          };

          clusterConfigBase = {
            suffix = config.domain.suffix;
            clusters = forEachAttrIn config.domain.clusters (
              clusterName: clusterDefinition:

              rec {

                fqdn = "${clusterName}.${config.domain.suffix}";
                name = "${clusterName}";

                # users TODO: add users?

                services = forEachAttrIn clusterDefinition.services (
                  serviceName: serviceDefinition:

                  attrsets.recursiveUpdate
                    {
                      name = serviceName;
                      roles = (
                        forEachAttrIn serviceDefinition.roles (
                          roleName: role:
                          lists.forEach (filters.resolveMachineName role clusterName config) (
                            machineName: machines."${machineName}"
                          )
                        )
                      );
                      selectors = lists.forEach (
                        # comment to force linebreak in formatter
                        filters.resolveMachineName serviceDefinition.selectors clusterName config
                      ) (machineName: machines."${machineName}");
                    }

                    (
                      removeAttrs serviceDefinition [
                        "selectors"
                        "roles"
                        "definition"
                        "extraConfig"
                      ]
                    )

                );

                machines = forEachAttrIn clusterDefinition.machines (
                  machineName: machineDefinition:

                  attrsets.recursiveUpdate
                    {
                      name = machineName;
                      ips = get.ips machineDefinition.nixosConfiguration.config;
                      fqdn = machineDefinition.nixosConfiguration.config.networking.fqdn;
                      serviceAddresses = lists.forEach machineDefinition.serviceAddresses (entry: entry.tag);
                      services = lib.attrNames machineDefinition.services;
                      config = machineDefinition.nixosConfiguration.config;
                    }
                    (
                      builtins.removeAttrs machineDefinition [
                        "nixosConfiguration"
                        "nixosModules"
                        "services"
                        "users"
                      ]
                    )

                );

              }
              // (removeAttrs clusterDefinition [
                "machines"
                "services"
                "users"
              ])
            );
          };
        in
        if clusterName != null then
          if machineName != null then clusterConfigMachineResolved else clusterConfigClusterResolved
        else
          clusterConfigBase;

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

    clusterMachines = config: clusterName: config.domain.clusters."${clusterName}".machines;

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

    interface = {
      ips =
        interfaceDefinition:
        let
          v4Addresses = lists.forEach interfaceDefinition.ipv4.addresses (
            addressDefinition: addressDefinition.address
          );
          v6Addresses = lists.forEach interfaceDefinition.ipv6.addresses (
            addressDefinition: addressDefinition.address
          );
        in
        lists.flatten [
          v4Addresses
          v6Addresses
        ]
        ++ (
          if interfaceDefinition ? useDHCP && interfaceDefinition.useDHCP == true then [ "dhcp" ] else [ ]
        );

      definitions =
        config:
        lists.forEach (get.interface.names config) (interfaceName: {
          "${interfaceName}" =
            builtins.removeAttrs (builtins.getAttr interfaceName config.networking.interfaces)
              [ "subnetMask" ];
        });

      names = config: attrsets.attrNames config.networking.interfaces;
    };

    ips =
      config:
      let
        interfaces = attrsets.mergeAttrsList (
          lists.forEach (get.interface.definitions config) (
            interface:
            let
              interfaceName = (lists.head (attrsets.attrNames interface));
              interfaceValue = (lists.head (attrsets.attrValues interface));
            in
            {
              "${interfaceName}" = get.interface.ips interfaceValue;
            }
          )
        );
      in
      interfaces;

  };

  # change the attributes on a clusterConfig level, keep unmentioned values
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

  # Defines a list machine annotations.
  # AnnotationPath is a '.' separated path or name of the annotation
  # all other options are the same as in lib.mkOption
  # example:
  # options = clusterlib.mkAnnotations [
  #   {
  #     annotationPath = "kubernetes.nodeLabels";
  #     description = "A set of labels that will be added to the node when registered in the kubernetes cluster.";
  #     type = lib.types.attrsOf lib.types.str;
  #     default = { };
  #   }
  #   {
  #     annotationPath = "kubernetes.keepalived.publicNatInterfaces";
  #     type = lib.types.listOf lib.types.str;
  #     default = [ ];
  #   }
  # ];
  mkAnnotations =
    annotations:
    let
      # Create one attrset per annotation
      annotationAttrs = map (
        annotation:
        lib.attrsets.setAttrByPath (lib.splitString "." annotation.annotationPath) (
          lib.mkOption (removeAttrs annotation [ "annotationPath" ])
        )
      ) annotations;

      # Merge all generated attrsets together
      options.annotations = lib.foldl' lib.recursiveUpdate { } annotationAttrs;

      annotatedMachineType = {
        inherit options;
      };
    in
    {
      domain = domainType { clusterType = clusterType { machineType = annotatedMachineType; }; };
    };

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
        # services = mkOption { type = attrsOf (submodule clusterServiceType); };
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

        # virtualization = mkOption { type = attrsOf (submodule virtualizationType); };

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
    mkAnnotations
    overwrite
    update
    ;
}
