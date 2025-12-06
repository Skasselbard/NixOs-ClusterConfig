{ flakeInputs }:

# Notes:

# TODO: Tooling goals:
# a tool should be able to parse the config and build views; e.g.:
#   - hardware info (maybe also retrieved by ssh)
#   - vm configuration
#   - configured hosts with type and ip configuration
#   - a list of dns names with ip and usage information
#   - version information
#   - k3s information (configured and retrieved)
#   - configured users on different machines
#   - configured interfaces and ips
#   - imported views for each configured service

let # imports

  pkgs = import flakeInputs.nixpkgs {
    # the exact value of 'system' should be unimportant since we only use lib
    # TODO: is the above statement still true?
    system = "x86_64-linux";
  };

  lib = pkgs.lib;

  clusterlib =
    with flakeInputs;
    import ./lib.nix {
      inherit nixpkgs flake-utils;
      lib = pkgs.lib;
    };

  filters = import ./filters.nix { lib = pkgs.lib; };
  add = clusterlib.add;
  update = clusterlib.update;
  forEachAttrIn = clusterlib.forEachAttrIn;

  lists = lib.lists;
  attrsets = lib.attrsets;
  evalModules = lib.evalModules;
  head = builtins.head;

in

let

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
        ./options.nix
        ./extensionOptions.nix
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

  # TODOs:
  # - conditionally include virtual interfaces (networking.interfaces.<name>.virtual = true) -> not useful for dns
  # - include dhcp hints for static dhcp ip -> known dhcp ips should be addable
  # tagging
  # - cluster annotations: fqdn, all ips, all machine names + fqdns, all service names, service selectors per service
  # maybe define cluster groups in the same way as services und users

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
      # Annotate the cluster with data from the configurations
      # This includes:
      # - the used IP addresses
      # - the FQDN
      # - resolved filters
      # evalAnnotatedCluster = annotate machineEvaluatedCluster;

      # Step 5:
      # Transform the machine configurations (and the cluster configuration)
      serviceAnnotatedCluster = applyClusterTransformations machineEvaluatedCluster machineEvaluatedCluster.extensions.transformations.moduleTransformations;

      # Step 6:
      # Evaluate the final NixosConfigurations that can be added as build targets
      nixosConfiguredCluster = evalMachines serviceAnnotatedCluster;

      # TODO: Consider another extension step
      # Reasoning: In the previous extension step (moduleTransformations) the nixos configuration of each machine
      # is missing the service modules.
      # If we want to add transformations that depend on the final nixos configuration (including services),
      # we need another evaluation and extension step here.

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
