{
  lib,
  clusterlib,
  flakeInputs,
  ...
}:
let
  # imports
  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;

  mkOption = lib.mkOption;
  lists = lib.lists;
  attrsets = lib.attrsets;

  listOf = lib.types.listOf;
  raw = lib.types.raw;

  home-manager = flakeInputs.home-manager;

  # redefine types to nest submodules at the right place
  domainType = clusterlib.domainType { inherit clusterType; };
  clusterType = clusterlib.clusterType {
    inherit machineType;
    inherit userType;
  };
  machineType = clusterlib.machineType { inherit userType; };

  # define home-manager options
  userType.options.homeManagerModules = mkOption {
    description = ''
      A list of modules included by homeManager.

      Home manager has its own module system which is evaluated independently from the NixOs modules.
      However, the form of home manager modules is identical to NixOs modules.

      This list will not be evaluated by the cluster configuration.
      It will be directly forwarded to home manager on the corresponding nodes in the cluster.
    '';
    type = listOf raw;
    default = [ ];
  };

  # Config transformation to add home manager modules for each user
  homeManagerAnnotation =
    config:

    # Add NixOs modules inferred by the cluster config to each nodes NixOs modules
    add.nixosModule config (
      clusterName: nodeName: nodeConfig:
      let

        clusterUsers = config.domain.clusters."${clusterName}".users;
        nodeUsers = nodeConfig.users;

        clusterHomeManagerModules = forEachAttrIn clusterUsers (
          n: userConfig: userConfig.homeManagerModules
        );
        nodeHomeManagerModules = forEachAttrIn nodeUsers (n: userConfig: userConfig.homeManagerModules);

        mergedHomeManagerModules = lists.flatten [
          (attrsets.attrValues clusterHomeManagerModules)
          (attrsets.attrValues nodeHomeManagerModules)
        ];
        activateHomeManager = mergedHomeManagerModules != [ ];

      in
      (
        if activateHomeManager then
          [

            # homeManager config
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              # Use a set of all users to acces the homeManager module list for each user.
              # Ignore the actual definition for the user and access the module list directly.
              home-manager.users = forEachAttrIn (clusterUsers // nodeUsers) (
                user: _ignore:
                let
                  clusterModules =
                    if clusterHomeManagerModules ? "${user}" then clusterHomeManagerModules."${user}" else [ ];
                  nodeModules = if nodeHomeManagerModules ? "${user}" then nodeHomeManagerModules."${user}" else [ ];
                in
                {
                  imports = (clusterModules ++ nodeModules);
                }
              );
            }
          ]
        else
          [ ]
      )
    );

in
{
  options.domain = domainType;
  config.extensions.transformations.clusterTransformations = [ homeManagerAnnotation ];
}
