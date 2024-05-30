{ pkgs, lib, clusterlib, flake-utils, nixos-anywhere, ... }:

let # imports
  forEachAttrIn = clusterlib.forEachAttrIn;
  get = clusterlib.get;
in with lib;
with lib.types;

let

  # redefine types to nest submodules at the right place
  domainType = clusterlib.domainType { inherit clusterType; };
  clusterType = clusterlib.clusterType { inherit machineType; };

  # defining deployment options for machines
  machineType.options.partitioning = {
    # TODO:
    formatScript = mkOption {
      description = "Used to format drives during a nixos-anywhere deployment";
      type = nullOr package;
      default = null;
    };
  };

  # Build nixos-anywhere setup script for remote installations in packages.$system.$machineName.setup
  deploymentAnnotation = config:
    let machines = get.machines config;
    in attrsets.recursiveUpdate config

    (flake-utils.lib.eachSystem flake-utils.lib.allSystems (system: {

      # buld an iso package for each machine configuration 
      packages = forEachAttrIn machines (machineName: machineConfig: {
        setup = let
          nixosConfig =
            machineConfig.nixosConfiguration.config.system.build.toplevel.outPath;
          formatScript =
            machineConfig.nixosConfiguration.config.partitioning.ephemeral_script;
        in pkgs.writeScriptBin "deploy" ''
          ${pkgs.nix}/bin/nix run path:${nixos-anywhere.outPath} -- -s ${formatScript.outPath} ${nixosConfig} ${machineConfig.deployment.targetUser}@${machineConfig.deployment.targetHost}
        '';
      });

    }));
in {

  options.domain = domainType;
  config.extensions.deploymentTransformations = [ deploymentAnnotation ];
}
