{
  pkgs,
  lib,
  clusterlib,
  flake-utils,
  ...
}:

let
  attrsets = lib.attrsets;

  get = clusterlib.get;
  add = clusterlib.add;

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

      # add the tooling scripts to the apps
      apps =
        # The apps are generated for all system  configurations (by using flake utils)
        (eachSystem allSystems (system: {
          apps.clusterConfig = {
            type = "app";
            program =
              (pkgs.writeShellScriptBin "clusterConfig" ''

                # add the package information to the environment for use in auto completion
                export packageInfo=$(${pkgs.nushell}/bin/nu ${./tooling}/clusterInfo.nu packages)

                # run a nu environment with imported tooling scripts to make the functions available as commands
                ${pkgs.nushell}/bin/nu -e "
                  source ${./tooling}/clusterInfo.nu;
                  source ${./tooling}/clusterConfig.nu
                  "

              '').outPath
              + "/bin/clusterConfig";
          };
        })).apps;

    };

  packageAnnotation =
    config: config // { packageInfo = (removeDerivations config.packages."x86_64-linux"); };

  connectionAnnotation =
    config:
    add.machinePackages config (
      machineName: machineConfig: config: {

        connect =
          let
            cfg = machineConfig.deployment;
            host = cfg.targetHost;
            user = if cfg ? targetUser && cfg.targetUser != null then cfg.targetUser + "@" else "";
          in
          pkgs.writeScriptBin "connectTo-${machineName}" "${pkgs.openssh}/bin/ssh ${user}${host} \${@:1}";

      }
    );

in
{
  config.extensions.deploymentTransformations = [
    appsAnnotation
    connectionAnnotation
  ];
  config.extensions.infoTransformations = [
    clusterInfoAnnotation
    packageAnnotation
  ];
}
