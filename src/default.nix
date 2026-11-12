{ flakeInputs }:

let # imports

  lib = flakeInputs.nixpkgs.lib;

  clusterlib =
    with flakeInputs;
    import ./lib.nix {
      inherit lib nixpkgs flake-utils;
    };

  filters = import ./filters.nix { inherit lib; };
  add = clusterlib.add;
  evalModules = lib.evalModules;

  # Internal pipeline step: copies cluster services onto the nodes their
  # selectors resolve to. Not part of `extensions.transformations` on purpose,
  # see src/serviceSelection.nix and doc/Decisions.md (D3).
  serviceSelection = import ./serviceSelection.nix { inherit lib clusterlib filters; };

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
      packageSystem = clusterConfig.packageSystem or "x86_64-linux";
      pkgs = import flakeInputs.nixpkgs { system = packageSystem; };
    in
    evalModules {
      modules = clusterModules ++ [
        ./deployment.nix
        ./transformations.nix
        ./services.nix
        ./modules/tooling.nix
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
      evaluatedCluster = (evalCluster config).config // {
        packageSystem = config.packageSystem or "x86_64-linux";
      };

      validatedCluster = (import ./validation.nix { inherit lib clusterlib filters; }) evaluatedCluster;

      # Step 2:
      # Transform the cluster configuration
      clusterAnnotatedCluster = applyClusterTransformations validatedCluster validatedCluster.extensions.transformations.clusterTransformations;

      # Step 3:
      # Evaluate the nixosModules from all machines to generate a first NixosConfiguration.
      # This config will be overwritten later.
      machineEvaluatedCluster = evalMachines clusterAnnotatedCluster;

      # Step 4:
      # Validate the selectors of all services, then select the services for
      # every node.
      #
      # Selectors are validated and resolved after the first node evaluation, so
      # they may query evaluated machine options (filters.machineOption) without
      # an additional evaluation round. Service selection is an internal step
      # rather than a cluster transformation for the same reason.
      selectorsCheckedCluster = (import ./validate-selectors.nix { inherit lib filters; }) machineEvaluatedCluster;
      serviceSelectedCluster = serviceSelection selectorsCheckedCluster;

      # Step 5:
      # Transform the machine configurations (and the cluster configuration)
      serviceAnnotatedCluster = applyClusterTransformations serviceSelectedCluster serviceSelectedCluster.extensions.transformations.moduleTransformations;

      # Step 6:
      # Evaluate the final NixosConfigurations that can be added as build targets
      guestConfiguredCluster = evalMachines serviceAnnotatedCluster;
      hostsAnnotatedCluster = applyClusterTransformations guestConfiguredCluster guestConfiguredCluster.extensions.transformations.hostTransformations;
      nixosConfiguredCluster = hostsAnnotatedCluster;

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
