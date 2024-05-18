{ lib, home-manager, clusterlib, ... }:
let # imports

  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;

in with lib;
with lib.types;
let

  # redefine types to nest submodules at the right place
  domainType = clusterlib.domainType { inherit clusterType; };
  clusterType = clusterlib.clusterType {
    inherit machineType;
    inherit userType;
  };
  machineType = clusterlib.machineType { inherit userType; };

  # define home-manager options
  userType.options.homeManagerModules = mkOption {
    description = mdDoc ''
      A list of modules included by homeManager.

      Home manager has its own module system which is evaluated independantly from the NixOs modules.
      However, the form of home manager modules is identical to NixOs modules.

      This list will not be evaluated by the cluster configuration.
      It will be directly forwarded to home manager on the corresponding machines in the cluster.
    '';
    type = listOf raw;
    default = [ ];
  };

  # Config transformation to add home manager modules for each user
  homeManagerAnnotation = config:

    # Add NixOs modules inferred by the cluster config to each Machines NixOs modules
    add.nixosModule config (clusterName: machineName: machineConfig:
      let

        clusterUsers = config.domain.clusters."${clusterName}".users;
        machineUsers = machineConfig.users;

        clusterhomeManagerModules = forEachAttrIn clusterUsers
          (n: userConfig: userConfig.homeManagerModules);
        machineHomeManagerModules = forEachAttrIn machineUsers
          (n: userConfig: userConfig.homeManagerModules);

        mergedHomeManagerModules = lists.flatten [
          (attrsets.attrValues clusterhomeManagerModules)
          (attrsets.attrValues machineHomeManagerModules)
        ];
        activateHomeManager = mergedHomeManagerModules != [ ];

      in (if activateHomeManager then [

        # homeManager config
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;

          # Use a set of all users to acces the homeManager module list for each user.
          # Ignore the actual definition for the user and access the module list directly.
          home-manager.users = forEachAttrIn (clusterUsers // machineUsers)
            (user: _ignore:
              let
                clusterModules = if clusterhomeManagerModules ? "${user}" then
                  clusterhomeManagerModules."${user}"
                else
                  [ ];
                machinModules = if machineHomeManagerModules ? "${user}" then
                  machineHomeManagerModules."${user}"
                else
                  [ ];
              in { imports = (clusterModules ++ machinModules); });
        }
      ] else
        [ ]));

in {
  options.domain = domainType;
  config.extensions.clusterTransformations = [ homeManagerAnnotation ];
}
