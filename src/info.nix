{
  pkgs,
  lib,
  clusterlib,
  flakeInputs,
  ...
}:

let
  attrsets = lib.attrsets;

  get = clusterlib.get;

  flake-utils = flakeInputs.flake-utils;

  eachSystem = flake-utils.lib.eachSystem;
  allSystems = flake-utils.lib.allSystems;

  removeTypes =
    config: ((lib.attrsets.filterAttrsRecursive (attrName: attrValue: (attrName != "_type"))) config);

  removeDerivations =
    attrset:
    lib.attrsets.mapAttrs (
      name: value:
      if (builtins.isAttrs value && attrsets.isDerivation value) then
        value.name
      else if builtins.isAttrs value then
        removeDerivations value
      else
        value
    ) attrset;

  clusterInfoAnnotation = config: removeTypes (get.clusterInfo config);

  appsAnnotation =
    config:

    attrsets.recursiveUpdate config {

      # TODO: rework of the cluster config app
      #   # add the tooling scripts to the apps
      #   apps =
      #     # The apps are generated for all system  configurations (by using flake utils)
      #     (eachSystem allSystems (system: {
      #       apps.clusterConfig = {
      #         type = "app";
      #         program =
      #           (pkgs.writeShellScriptBin "clusterConfig" ''

      #             # add the package information to the environment for use in auto completion
      #             export packageInfo=$(${pkgs.nushell}/bin/nu ${./tooling}/clusterInfo.nu packages)

      #             # run a nu environment with imported tooling scripts to make the functions available as commands
      #             ${pkgs.nushell}/bin/nu -e "
      #               source ${./tooling}/clusterInfo.nu;
      #               source ${./tooling}/clusterConfig.nu
      #               "

      #           '').outPath
      #           + "/bin/clusterConfig";
      #       };
      #     })).apps;

    };

  packageAnnotation =
    config: config // { packageInfo = (removeDerivations config.packages."x86_64-linux"); };

in
{
  # TODO: Tooling goals:
  # a tool should be able to parse the config and build views; e.g.:
  #   - vm configuration
  #   - configured hosts with type and ip configuration
  #   - a list of dns names with ip and usage information
  #   - version information
  #   - configured users on different machines
  #   - configured interfaces and ips
  #   - imported views for each configured service

  config.extensions = {

    # transformations.deploymentTransformations = [
    #   appsAnnotation
    # ];

    transformations.infoTransformations = [
      clusterInfoAnnotation
      packageAnnotation
    ];

    clusterMachine = {
      packages = {

        connect =
          { clusterConfig }:
          let
            this = clusterConfig.clusters.this.machines.this;
            machineName = this.name;
            cfg = this.deployment;
            host = cfg.targetHost;
            user = if cfg ? targetUser && cfg.targetUser != null then cfg.targetUser + "@" else "";
          in
          pkgs.writeShellScriptBin "connectTo-${machineName}" "${pkgs.openssh}/bin/ssh ${user}${host} \${@:1}";

      };
    };
  };
}
