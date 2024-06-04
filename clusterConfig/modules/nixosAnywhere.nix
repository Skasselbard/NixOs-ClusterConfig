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
  machineType.options.deployment = {
    # TODO:
    formatScript = mkOption {
      description = ''
      Used to format drives during a nixos-anywhere deployment.
      
      If set to `null` no format script will be executed while deploying nixos anywhere.
      If set to `"disko"` the default [disko](https://github.com/nix-community/disko) format script is run.
      If set to a executable script, this script is run.

      Nixos Onywhere can be run with `nix run .#hostname.create`.
      Additionally, the format script can be run remotly with `nix run .#hostname.format`.
      '';
      type = nullOr either package enum ["disko"];
      default = null;
    };
  };

  # Build nixos-anywhere setup script for remote installations in packages.$system.$machineName.create
  deploymentAnnotation = config:
    let machines = get.machines config;
    in attrsets.recursiveUpdate config

    (flake-utils.lib.eachSystem flake-utils.lib.allSystems (system: {

      # build an iso package for each machine configuration
      packages = forEachAttrIn machines (machineName: machineConfig: {
        create = let
          nixosConfig =
            machineConfig.nixosConfiguration.config.system.build.toplevel.outPath;
          formatScript = if machineConfig.deployment.formatScript == null then else
            machineConfig.deployment.formatScript;
        in pkgs.writeScriptBin "deploy" ''
          ${pkgs.nix}/bin/nix run path:${nixos-anywhere.outPath} -- -s ${formatScript.outPath} ${nixosConfig} ${machineConfig.deployment.targetUser}@${machineConfig.deployment.targetHost}
        '';
        # TODO: format: ... if formatScritp == null then "echo no format script configured" else run formatScript;
      });

    }));
in {

  options.domain = domainType;
  config.extensions.deploymentTransformations = [ deploymentAnnotation ];
}
