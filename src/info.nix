{
  pkgs,
  lib,
  clusterlib,
  ...
}:

let
  attrsets = lib.attrsets;

  get = clusterlib.get;

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
