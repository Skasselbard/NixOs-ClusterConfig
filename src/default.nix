{ flakeInputs }:

let # imports

  pkgs = import flakeInputs.nixpkgs {
    # the exact value of 'system' should be unimportant since we only use lib
    system = "x86_64-linux";
  };

  lib = pkgs.lib;

  clusterlib =
    with flakeInputs;
    import ./lib.nix {
      inherit lib nixpkgs flake-utils;
    };

  filters = import ./filters.nix { inherit lib; };
  add = clusterlib.add;
  evalModules = lib.evalModules;

  # Use the NixOs module system to evaluate the clusterConfig
  #
  # - Add a list of clusterConfigModules from 'clusterConfig.modules' to the module list
  # - Add the clusterConfig default modules
  # - Forward required flake inputs to _module.args to make them available in the imported modules
  # - Set the evaluated config attribute to the initial value
  evalCluster =
    clusterConfig:
    let
      clusterModules = if clusterConfig ? modules then clusterConfig.modules else [ ];
    in
    evalModules {
      modules = clusterModules ++ [
        ./deployment.nix
        ./transformations.nix
        ./services.nix
        ./options/options.nix
        ./options/extensionOptions.nix
        # ./info.nix
        {
          config = {
            _module.args = {
              # make clusterlib available
              clusterlib = clusterlib // {
                inherit buildCluster filters;
              };
              inherit
                pkgs
                lib
                filters
                flakeInputs # make all flake inputs available
                ;
            };
            # set the domain attribute for evaluation
            domain = clusterConfig.domain;
          };
        }
      ];
    };

  # Add a 'nixosConfiguration' attribute to each machine configuration,
  # (e.g. domain.cluster.{clustername}.machines.{machinename}.nixosConfiguration)
  # wich holds an evaluated system configuration based on the modules defined for the machine.
  evalMachines = config: add.nixosConfigurations config;

  # Applies a list of transformations to a clusterConfig.
  # The transformations need to be functions that take a clusterConfig and return a (modified) clusterConfig
  applyClusterTransformations =
    config: transformations:
    builtins.foldl' (
      currentConfig: transformator: (transformator currentConfig)
    ) config transformations;

  # a function that builds and evaluates the clusterConfig to apply directly on the cluster definition
  buildCluster =
    config:
    let
      # Step 1:
      # Evaluate the cluster to check for type conformity
      evaluatedCluster = (evalCluster config).config;

      # Step 2:
      # Transform the cluster configuration
      clusterAnnotatedCluster = applyClusterTransformations evaluatedCluster evaluatedCluster.extensions.transformations.clusterTransformations;

      # Step 3:
      # Evaluate the nixosModules from all machines to generate a first NixosConfiguration.
      # This config will be overwritten later.
      machineEvaluatedCluster = evalMachines clusterAnnotatedCluster;

      # Step 4:
      # DEPRECATED!

      # Step 5:
      # Transform the machine configurations (and the cluster configuration)
      serviceAnnotatedCluster = applyClusterTransformations machineEvaluatedCluster machineEvaluatedCluster.extensions.transformations.moduleTransformations;

      # Step 6:
      # Evaluate the final NixosConfigurations that can be added as build targets
      nixosConfiguredCluster = evalMachines serviceAnnotatedCluster;

      # Step 7:
      # Transformations to add packages for deployment scripts and other tools
      deploymentAnnotatedCluster = applyClusterTransformations nixosConfiguredCluster nixosConfiguredCluster.extensions.transformations.deploymentTransformations;

      # Step 8:
      # Transformations to generate cluster information
      infoAnnotatedCluster = applyClusterTransformations deploymentAnnotatedCluster deploymentAnnotatedCluster.extensions.transformations.infoTransformations;

    in
    infoAnnotatedCluster;
in
{
  inherit buildCluster filters;
}
