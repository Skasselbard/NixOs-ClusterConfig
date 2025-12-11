{ lib, clusterlib, ... }:
let # imports

  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;
  eval = clusterlib.eval;
  update = clusterlib.update;

  attrsets = lib.attrsets;
  mkDefault = lib.mkDefault;

  # helperFunctions

  # Detect if a value looks like a function expecting clusterConfig.
  # A valid function must accept an attrset and must reference "clusterConfig"
  # inside the parameter set definition.
  isClusterConfigFn =
    fn:
    builtins.isFunction fn
    && (builtins.elem "clusterConfig" (builtins.attrNames (builtins.functionArgs fn)));

  # Recursively traverse arbitrary attrsets.
  # - If attrset → recurse
  # - If is function expecting clusterConfig → call it
  # - Else → warn and drop
  callLeafFunctions =
    { clusterConfig, node }:
    if builtins.isAttrs node then
      # Recurse through all attributes of the attrset
      builtins.mapAttrs (
        _: child:
        callLeafFunctions {
          inherit clusterConfig;
          node = child;
        }
      ) node
    else if isClusterConfigFn node then
      # Call the function with the clusterConfig argument
      node { inherit clusterConfig; }
    else
      throw "ERROR: Value '${toString node}' is not a function expecting { clusterConfig, ... }.";

  # Add NixOs modules inferred by the cluster config to each Machines NixOs modules
  # This includes:
  # - HostNames: networking.hostname is set to the name of the machine definition
  # - DomainName: networking.domain is set to clusterName.domainSuffix
  # - HostPlatform: pkgs.hostPlatform is set to the configured system in the machine configuration
  # - UserDefinitions: users.users is set with information from cluster-users and machine-users
  clusterTransformation =
    config:

    add.nixosModule config (
      clusterName: machineName: machineConfig:
      let

        clusterUsers = config.domain.clusters."${clusterName}".users;
        machineUsers = machineConfig.users;

      in
      [
        {
          # make clusterlib available for machine and service configs
          _module.args = {
            inherit clusterlib;
          };
        }

        {
          # add options for the config that is set by the cluster config
          imports = [ ((import ./options/nixosOptions.nix) { inherit config clusterlib; }) ];
        }

        {
          # machine config
          networking.hostName = machineName;
          networking.domain = clusterName + "." + config.domain.suffix;
          nixpkgs.hostPlatform = mkDefault machineConfig.system;
        }

        # make different modules for cluster and user definitions so that the NixOs
        # module system handles the merging

        {
          # cluster users
          users.users = forEachAttrIn clusterUsers (n: userConfig: userConfig.systemConfig);
          # forEach user (homeManagerModules ++ userHMModules) -> if not empty -> enable HM
        }

        {
          # machine users
          users.users = forEachAttrIn machineUsers (n: userConfig: userConfig.systemConfig);
        }

      ]
    );

  moduleTransformation =
    config:

    add.nixosModule config (
      clusterName: machineName: machineConfig: [
        {
          # make the cluster config available in in the ``config`` attribute during machine evaluation
          clusterConfig = (eval.clusterConfig config { inherit clusterName machineName; });
        }
      ]
    );

  lateConfigTransformation =
    config:

    lib.foldl (acc: elem: attrsets.recursiveUpdate acc elem) config [

      (update.clusters config (
        clusterName: clusterConfig:

        forEachAttrIn config.extensions.cluster.late.config (
          configName: configClosure:

          # call the closure with the evaluated cluster config representation
          callLeafFunctions {
            node = configClosure;
            clusterConfig = (eval.clusterConfig config { inherit clusterName; });
          }
        )
      ))

      (update.services config (
        clusterName: serviceName: serviceConfig:

        forEachAttrIn config.extensions.clusterServices."${serviceName}".late.config (
          configName: configClosure:

          # call the closure with the evaluated cluster config representation
          callLeafFunctions {
            node = configClosure;
            clusterConfig = (eval.clusterConfig config { inherit clusterName; });
          }
        )
      ))

      (update.machines config (
        clusterName: machineName: machineConfig:

        forEachAttrIn config.extensions.clusterMachine.late.config (
          configName: configClosure:

          # call the closure with the evaluated cluster config representation
          callLeafFunctions {
            node = configClosure;
            clusterConfig = (eval.clusterConfig config { inherit clusterName machineName; });
          }
        )
      ))

    ];

  packageTransformation =
    config:

    lib.foldl (acc: elem: attrsets.recursiveUpdate acc elem) config (
      [

        # Add a package for each cluster to the flake output
        (add.clusterPackage config (
          clusterName:

          # For each script a package is added
          forEachAttrIn config.extensions.cluster.packages (
            scriptName: scriptClosure:

            # call the script closure with the evaluated cluster config representation
            callLeafFunctions {
              node = scriptClosure;
              clusterConfig = (eval.clusterConfig config { inherit clusterName; });
            }
          )
        ))

        # Add a package for each machine to the flake output
        (add.machinePackages config (
          clusterName: machineName:

          # For each script a package is added
          forEachAttrIn config.extensions.clusterMachine.packages (
            scriptName: scriptClosure:

            # call the script closure with the evaluated cluster config representation
            callLeafFunctions {
              node = scriptClosure;
              clusterConfig = (eval.clusterConfig config { inherit clusterName machineName; });
            }

          )
        ))

      ]
      ++ (lib.attrValues (
        # For all services the package extensions are evaluated
        forEachAttrIn config.extensions.clusterServices (
          serviceName: serviceDefinition:

          # Add a package for each service to the flake output
          (add.servicePackages config serviceName (
            clusterName:

            (forEachAttrIn serviceDefinition.packages (
              scriptName: scriptClosure:

              # call the script closure with the evaluated cluster config representation
              callLeafFunctions {
                node = scriptClosure;
                clusterConfig = (eval.clusterConfig config { inherit clusterName; });
              }
            ))
          ))
        )
      ))
    );

  nixosModuleTransformations =
    config:
    add.nixosModule config (
      _: _: _:
      config.extensions.clusterMachine.nixosModules
    );

in
{

  config.extensions.transformations = {

    clusterTransformations = [ clusterTransformation ];

    moduleTransformations = [
      moduleTransformation
      nixosModuleTransformations
    ];

    deploymentTransformations = [
      # order is important
      lateConfigTransformation
      packageTransformation
    ];

  };

}
