{ lib, clusterlib, nixpkgs, colmena, ... }:
let
  forEachAttrIn = clusterlib.forEachAttrIn;
  get = clusterlib.get;
in with lib;

let

  # Build the deployment scripts and functions including
  # - colmena hive definition for remote deployment
  # - colmena app import to run colmena from the flake with 'nix run .#colmena [colmena-sub-cmd] -- [colmenaOptions]'
  deploymentAnnotation = config:
    let machines = get.machines config;
    in attrsets.recursiveUpdate config {

      apps = colmena.apps;

      colmena = {
        meta.nixpkgs = import nixpkgs {
          system = "x86_64-linux"; # TODO: is this used for all machines?
          overlays = [ ];
        };
      } // forEachAttrIn machines (machineName: machineConfig: {
        deployment = machineConfig.deployment;
        imports = machineConfig.nixosModules;
      });

    };
in {
  imports = [
    ../deployment.nix # explicitly load colmena options from deployment definition
  ];
  config.extensions.deploymentTransformations = [ deploymentAnnotation ];
}
