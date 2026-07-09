{
  lib,
  nixpkgs,
  flake-utils,
}:
let
  # imports
  filters = import ./filters.nix { inherit lib; };
  vmlib = import ./modules/vms/lib.nix { inherit lib; };

  attrsets = lib.attrsets;
  lists = lib.lists;
  concatStringsSep = lib.concatStringsSep;
  splitString = lib.splitString;

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

    # Evaluates the 'nixosModules' for each node and adds the resulting nixosConfiguration to the node config.
    nixosConfigurations =
      config:
      update.nodes config (
        clusterName: nodeName: nodeConfig: {
          nixosConfiguration = nixpkgs.lib.nixosSystem { system = nodeConfig.system; modules = nodeConfig.nixosModules; };
        }
      );

    # Adds a NixosModule build by 'moduleConfigFn' to each node.
    # The moduleConfigFn builds a nixos module from three input parameters (clusterName, nodeName, nodeConfig).
    # clusterconfig -> ((clusterName -> nodeName -> nodeConfig) -> moduleAttr) -> clusterconfig
    nixosModule =
      config: moduleConfigFn:
      update.nodes config (
        clusterName: nodeName: nodeConfig: {
          nixosModules =
            (lists.flatten [ (moduleConfigFn clusterName nodeName nodeConfig) ]) ++ nodeConfig.nixosModules;
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

              forEachAttrIn (clusterDefinition.machines) (
                machineName: _machineDefinition: updatePackageFn clusterName machineName
              )

            );

          })).packages;
      };

    # Add a package that can be build with `nix build #clusterName.vmName.package` or run with `nix run #clusterName.vmName.package`
    # updatePackageFn =  clusterName -> vmName -> {attrName = derivation;}
    vmPackages =
      config: updatePackageFn:
      attrsets.recursiveUpdate config {

        packages =
          # The deployment options are generated for all system  configurations (by using flake utils)
          (flake-utils.lib.eachSystem flake-utils.lib.allSystems (system: {

            packages = forEachAttrIn config.domain.clusters (
              clusterName: clusterDefinition:

              forEachAttrIn (clusterDefinition.vms) (
                machineName: _machineDefinition: updatePackageFn clusterName machineName
              )

            );

          })).packages;
      };

    # Add a package that can be build with `nix build #clusterName.nodeName.package` or run with `nix run #clusterName.nodeName.package`
    # updatePackageFn =  clusterName -> nodeName -> {attrName = derivation;}
    nodePackages =
      config: updatePackageFn:
      add.vmPackages (add.machinePackages config updatePackageFn) updatePackageFn;

    # Add a package that can be build with `nix build #clusterName.nodeName.services.attrName` or run with `nix run #clusterName.nodeName.services.attrName`
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
        nodeName ? null, # if given, a "this" machine is added that points to the machine with the given name in the "this" cluster
      }:
      if builtins.isString nodeName && !builtins.isString clusterName then
        throw "trying to evaluate clusterConfig with nodeName but no clusterName"
      else if !builtins.isString clusterName && clusterName != null then
        throw "trying to evaluate clusterConfig with clusterName that is not a string"
      else if !builtins.isString nodeName && nodeName != null then
        throw "trying to evaluate clusterConfig with nodeName that is not a string"
      else
        let
          # Add cluster information including "this" pointer for the current cluster and machine/vm and node.
          clusterConfigNodeResolved = attrsets.recursiveUpdate clusterConfigBase {
            clusters.this =
              let
                thisCluster = clusterConfigBase.clusters."${clusterName}";
                thisMachine = thisCluster.machines."${nodeName}" or null;
                thisVm = thisCluster.vms."${nodeName}" or null;
                thisNode =
                  if thisMachine != null then
                    thisMachine
                  else if thisVm != null then
                    thisVm
                  else
                    throw "nodeName '${nodeName}' not found in cluster '${clusterName}' during clusterConfig evaluation";
              in
              attrsets.recursiveUpdate thisCluster {
                machines.this = thisMachine;
                vms.this = thisVm;
                nodes.this = thisNode;
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
                          lists.forEach (filters.resolveNodeName role clusterName config) (nodeName: nodes."${nodeName}")
                        )
                      );
                      selectors = lists.forEach (filters.resolveNodeName serviceDefinition.selectors clusterName config) (
                        nodeName: nodes."${nodeName}"
                      );
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

                machines = forEachAttrIn (clusterDefinition.machines) (
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
                      removeAttrs machineDefinition [
                        "nixosConfiguration"
                        "nixosModules"
                        "services"
                        "users"
                      ]
                    )

                );

                vms = forEachAttrIn (clusterDefinition.vms) (
                  vmName: vmDefinition:

                  attrsets.recursiveUpdate
                    {
                      name = vmName;
                      ips = get.ips vmDefinition.nixosConfiguration.config;
                      fqdn = vmDefinition.nixosConfiguration.config.networking.fqdn;
                      serviceAddresses = lists.forEach vmDefinition.serviceAddresses (entry: entry.tag);
                      services = lib.attrNames vmDefinition.services;
                      config = vmDefinition.nixosConfiguration.config;
                    }
                    (
                      removeAttrs vmDefinition [
                        "backend"
                        "nixosConfiguration"
                        "nixosModules"
                        "services"
                        "users"
                      ]
                    )

                );

                nodes = machines // vms;

              }
              // (removeAttrs clusterDefinition [
                "machines"
                "services"
                "users"
                "vms"
              ])
            );
          };
        in
        if clusterName != null then
          if nodeName != null then clusterConfigNodeResolved else clusterConfigClusterResolved
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

    vms =
      config:
      attrsets.mergeAttrsList (
        lists.flatten (
          attrsets.attrValues (
            forEachAttrIn config.domain.clusters (clusterName: clusterValue: clusterValue.vms or { })
          )
        )
      );

    nodes = config: get.machines config // get.vms config;

    clusterMachines = config: clusterName: config.domain.clusters."${clusterName}".machines;
    clusterVms = config: clusterName: config.domain.clusters."${clusterName}".vms or { };
    clusterNodes =
      config: clusterName: get.clusterMachines config clusterName // get.clusterVms config clusterName;

    vmHost =
      hostFqdn: config:
      let
        suffix = config.domain.suffix; # e.g. "com"
  
        # Strip the domain suffix if the FQDN ends with it
        withoutSuffix =
          let
            suffixParts = splitString "." suffix;
            suffixLen = builtins.length suffixParts;
            parts = splitString "." hostFqdn;
            trailing = concatStringsSep "." (lists.drop (builtins.length parts - suffixLen) parts);
          in
          if trailing == suffix then
            concatStringsSep "." (lists.take (builtins.length parts - suffixLen) parts)
          else
            hostFqdn; # assume suffix was not included
  
        parts = splitString "." withoutSuffix;
  
        # Try all split points from left to right:
        #   split at i means: machine = parts[0..i], cluster = parts[i+1..n-1]
        candidates = lib.imap0 (
          i: _:
          let
            machine = concatStringsSep "." (lists.take (i + 1) parts);
            cluster = concatStringsSep "." (lists.drop (i + 1) parts);
          in
          if
            config.domain.clusters ? "${cluster}" && config.domain.clusters."${cluster}".machines ? "${machine}"
          then
            {
              inherit cluster machine;
              valid = true;
            }
          else
            { valid = false; }
        ) parts;
  
        matches = builtins.filter (c: c.valid) candidates;
      in
      if matches == [ ] then
        throw ''
          Error: VM references host '${hostFqdn}' but no matching
          <machine>.<cluster> pair was found in the cluster config.
  
          Searched for any path: domain.clusters.<cluster>.machines.<machine>
          Available clusters: ${toString (builtins.attrNames config.domain.clusters)}
        ''
      else
        # Take the first match (there should only be one)
        (builtins.head matches);

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
          "${interfaceName}" = removeAttrs (builtins.getAttr interfaceName config.networking.interfaces) [
            "subnetMask"
          ];
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

    # updateNodeFn = clusterName -> nodeName -> nodeConfig -> nodeConfig
    nodes =
      config: updateNodeFn:
      update.clusters config (
        clusterName: clusterConfig: {
          machines = (
            forEachAttrIn clusterConfig.machines (
              machineName: machineConfig: machineConfig // (updateNodeFn clusterName machineName machineConfig)
            )
          );
          vms = (
            forEachAttrIn clusterConfig.vms (
              vmName: vmConfig: vmConfig // (updateNodeFn clusterName vmName vmConfig)
            )
          );
        }
      );

    # updateNodeFn = clusterName -> nodeName -> nodeConfig -> nodeConfig
    machines =
      config: updateNodeFn:
      update.clusters config (
        clusterName: clusterConfig: {
          machines = (
            forEachAttrIn clusterConfig.machines (
              machineName: machineConfig: machineConfig // (updateNodeFn clusterName machineName machineConfig)
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
    update
    ;
}
