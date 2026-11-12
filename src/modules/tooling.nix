{ pkgs, lib, ... }:

let
  clusterConfigPackage = import ../tooling { inherit pkgs lib; };

  toolApp = {
    type = "app";
    program = "${clusterConfigPackage}/bin/clusterConfig";
    meta.description = "ClusterConfig command-line interface";
  };

  # The CLI is a normal package, so it also appears in packageIndex and is
  # discoverable through list/show/run. Completion intentionally treats it like
  # any other package at the top level.
  toolIndexEntry = {
    attrPath = "clusterConfig";
    segments = [ "clusterConfig" ];
    kind = "tool";
    clusterName = null;
    group = null;
    packageName = "clusterConfig";
    description = "ClusterConfig command-line interface";
    longDescription = null;
    action = "run";
    destructive = false;
  };
in
{
  # This transformation runs in the deployment stage, after the base
  # packageTransformation and packageIndexTransformation have run. It:
  #   1. exposes the CLI as the clusterConfig/clcli/default apps;
  #   2. adds the package output and a development shell;
  #   3. re-adds the tool entry to the already-generated package index.
  #
  # The existing entry is filtered first because packageIndex was generated
  # before this package output existed. Without filtering, a future ordering
  # change could leave two clusterConfig entries.
  config.extensions.transformations.deploymentTransformations = [
    (config:
      let
        system = config.packageSystem;
        packages = config.packageIndex.packages or [ ];
        packagesWithoutTool = builtins.filter (entry: entry.attrPath != "clusterConfig") packages;
      in
      lib.recursiveUpdate config {
        apps.${system} = {
          # clusterConfig is canonical; clcli is the short alias. default makes
          # `nix run .#` open the CLI browser.
          clusterConfig = toolApp;
          clcli = toolApp;
          default = toolApp;
        };

        packages.${system}.clusterConfig = clusterConfigPackage;

        # A development shell keeps the CLI on PATH and points it at the
        # checkout that is currently opened.
        devShells.${system}.clusterConfig = pkgs.mkShell {
          packages = [ clusterConfigPackage ];
          shellHook = ''
            export CLUSTER_CONFIG_FLAKE="$PWD"
          '';
        };

        # Keep the tool visible to list/show/run and to shell completion.
        packageIndex.packages = packagesWithoutTool ++ [ toolIndexEntry ];
      }
    )
  ];
}
