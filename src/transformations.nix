{ lib, clusterlib, ... }:
let # imports

  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;
  eval = clusterlib.eval;
  get = clusterlib.get;

  attrsets = lib.attrsets;
  lists = lib.lists;
  mkDefault = lib.mkDefault;

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
          imports = [ ./nixosOptions.nix ];
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
      clusterName: machineName: machineConfig:
      let
        clusterConfigBase = eval.clusterConfig config;
        # clusterConfigBase =
        #   lib.debug.traceSeqN 3 clusterConfigBase0.clusters.example
        #     clusterConfigBase0;

      in
      [
        {
          # Add cluster information including "this" pointer for the current cluster and machine.
          clusterConfig = attrsets.recursiveUpdate clusterConfigBase {
            clusters.this = attrsets.recursiveUpdate clusterConfigBase.clusters."${clusterName}" {
              machines.this = clusterConfigBase.clusters."${clusterName}".machines."${machineName}";
            };
          };
        }
      ]
    );

in
{

  config.extensions.transformations = {
    clusterTransformations = [ clusterTransformation ];
    moduleTransformations = [ moduleTransformation ];
  };

}
