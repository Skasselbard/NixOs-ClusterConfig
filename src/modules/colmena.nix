{
  lib,
  clusterlib,
  nixpkgs,
  colmena,
  ...
}:
let
  forEachAttrIn = clusterlib.forEachAttrIn;
  get = clusterlib.get;

  attrsets = lib.attrsets;

  # Colmena options are already defined and used in the clusterConfig deployment options
  # Hopwever, to add our own deployment options to the colmena option preset, while still be able
  # to build the colmena attribute set, we need to filter the deployment attribute set
  # for only the colmena options.
  colmenaOptions =
    ((import "${colmena.outPath}/src/nix/hive/options.nix").deploymentOptions {
      inherit lib;
      name = "{hostname}";
    }).options.deployment;

  colmenaConfigFrom =
    deploymentConfig:
    let
      colmenaNames = attrsets.attrNames colmenaOptions;
    in
    attrsets.filterAttrs (name: _: builtins.elem name colmenaNames) deploymentConfig;

  # Build the deployment scripts and functions including
  # - colmena hive definition for remote deployment
  # - colmena app import to run colmena from the flake with 'nix run .#colmena [colmena-sub-cmd] -- [colmenaOptions]'
  deploymentAnnotation =
    config:
    let
      machines = get.machines config;
    in
    attrsets.recursiveUpdate config {

      apps = colmena.apps;

      colmena =
        {
          meta.nixpkgs = import nixpkgs {
            system = "x86_64-linux"; # TODO: is this used for all machines?
            overlays = [ ];
          };
        }
        // forEachAttrIn machines (
          machineName: machineConfig: {
            deployment = colmenaConfigFrom machineConfig.deployment;
            imports = machineConfig.nixosModules;
          }
        );

    };
in
{
  imports = [
    ../deployment.nix # explicitly load colmena options from deployment definition
  ];
  config.extensions.deploymentTransformations = [ deploymentAnnotation ];
}
