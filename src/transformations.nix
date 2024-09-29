{ lib, clusterlib, ... }:
let # imports

  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;

  mkDefault = lib.mkDefault;

in
let

  # Add NixOs modules inferred by the cluster config to each Machines NixOs modules
  # This includes:
  # - Hostnames: networking.hostname is set to the name of the machiene definition
  # - DomainName: networkinig.domain is set to clusterName.domainSuffix
  # - Hostplattform: pkgs.hostPlattform is set to the configured system in the machine configuration
  # - UserDefinitions: users.users is set with information from cluster-users and machine-users
  clusterAnnotation =
    config:

    add.nixosModule config (
      clusterName: machineName: machineConfig:
      let

        clusterUsers = config.domain.clusters."${clusterName}".users;
        machineUsers = machineConfig.users;

      in
      [

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

in
{

  config.extensions = {
    clusterTransformations = [ clusterAnnotation ];
  };

}
