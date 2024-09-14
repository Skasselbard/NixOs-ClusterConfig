{ nixpkgs, nixos-generators, colmena, flake-utils }:

# Notes:

# Tooling goals:
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

  pkgs = import nixpkgs {
    # the exact value of 'system' should be unimportant since we only use lib
    # TODO: is the above statement still true?
    system = "x86_64-linux";
  };

  lib = pkgs.lib;

  clusterlib = import ./lib.nix {
    inherit nixpkgs;
    lib = pkgs.lib;
  };

  filters = import ./filters.nix { lib = pkgs.lib; };
  add = clusterlib.add;
  update = clusterlib.update;
  forEachAttrIn = clusterlib.forEachAttrIn;

in with lib;

let

  get = {

    interface = {
      ips = interfaceDefinition:
        let
          v4Adresses = lists.forEach interfaceDefinition.ipv4.addresses
            (addressDefinition: addressDefinition.address);
          v6Adresses = lists.forEach interfaceDefinition.ipv6.addresses
            (addressDefinition: addressDefinition.address);
        in lists.flatten [ v4Adresses v6Adresses ];

      definitions = machineConfig:
        lists.forEach (get.interface.names machineConfig) (interfaceName: {
          "${interfaceName}" = builtins.removeAttrs
            (builtins.getAttr interfaceName
              machineConfig.config.networking.interfaces) [ "subnetMask" ];
        });

      names = machineConfig:
        attrsets.attrNames machineConfig.config.networking.interfaces;
    };

    ips = machineConfig:
      let
        interfaces = attrsets.mergeAttrsList
          (lists.forEach (get.interface.definitions machineConfig) (interface:
            let
              interfaceName = (head (attrsets.attrNames interface));
              interfaceValue = (head (attrsets.attrValues interface));
            in { "${interfaceName}" = get.interface.ips interfaceValue; }));
      in {
        all = lists.flatten (attrsets.attrValues interfaces);
      } // interfaces;

  };

  # Use the NixOs module system to evaluate the clusterConfig
  #
  # - Add a list of clusterConfigModules from 'clusterConfig.modules' to the module list
  # - Add the clusterConfig default modules
  # - Forward required flake inputs to _module.args to make them available in the imported modules
  # - Set the evaluated config attribute to the initial value
  evalCluster = clusterConfig:
    let
      clusterModules =
        if clusterConfig ? modules then clusterConfig.modules else [ ];
    in evalModules {
      modules = clusterModules ++ [
        ./deployment.nix
        ./transformations.nix
        ./services.nix
        ./options.nix
        ./info.nix
        {
          config = {
            # make flake inputs available for submodules
            _module.args = {
              colmena = lib.mkDefault colmena;
              inherit pkgs lib nixpkgs clusterlib flake-utils nixos-generators
                filters;
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

  annotate = config:
    let
      machineAnnotaion = update.machines config
        (clusterName: machineName: machineConfig: {
          annotations = {
            inherit clusterName machineName;
            ips = get.ips machineConfig.nixosConfiguration;
            fqdn = machineConfig.nixosConfiguration.config.networking.fqdn;
            # TODO: subnets?
          };
        });
      serviceAnnotation = update.services machineAnnotaion
        (clusterName: serviceName: serviceConfig: {
          annotations.selectors = lists.forEach
            (filters.resolve serviceConfig.selectors clusterName
              machineAnnotaion) (annotation: annotation.machineName);
          annotations.roles = (forEachAttrIn serviceConfig.roles
            (roleName: role:
              (lists.forEach (filters.resolve role clusterName machineAnnotaion)
                (annotation: annotation.machineName))));
        });
    in serviceAnnotation;

  # Applies a list of transformations to a clusterConfig.
  # The transformations need to be functions that take a clusterConfig and return a (modified) clusterConfig
  applyClusterTransformations = config: transformations:
    builtins.foldl'
    (currentConfig: transformator: (transformator currentConfig)) config
    transformations;

in {

  inherit filters;

  # TODOs:
  # - conditionally include virtual interfaces (networking.interfaces.<name>.virtual = true) -> not useful for dns
  # - include dhcp hints for static dhcp ip -> known dhcp ips should be addable
  # tagging
  # - cluster annotations: fqdn, all ips, all machine names + fqdns, all service names, service selectors per service
  # maybe define cluster groups in the same way as services und users

  # a function that builds and evaluates the clusterconfig to apply directly on the cluster definition
  buildCluster = config:
    let
      # Step 1:
      # Evaluate the cluster to check for type conformity
      evaluatedCluster = (evalCluster config).config;

      # Step 2:
      # Transform the cluster configuration
      clusterAnnotatedCluster = applyClusterTransformations evaluatedCluster
        evaluatedCluster.extensions.clusterTransformations;

      # Step 3:
      # Evaluate the nixosModules from all machines to generate a first NixosConfiguration.
      # This config will be overwritten later.
      machineEvaluatedCluster = evalMachines clusterAnnotatedCluster;

      # Step 4:
      # Annotate the cluster with data from the configurations
      # This includes:
      # - the used IP addresses
      # - the FQDN
      # - resolved filters
      evalAnnotatedCluser = annotate machineEvaluatedCluster;

      # Step 5:
      # Transform the machine configurations (and the cluster configuration)
      serviceAnnotatedCluster = applyClusterTransformations evalAnnotatedCluser
        evalAnnotatedCluser.extensions.moduleTransformations;

      # Step 6:
      # Evaluate the final NixosConfigurations that can be added as build targets
      nixosConfiguredCluster = evalMachines serviceAnnotatedCluster;

      # Step 7:
      # Final transformations
      deploymentAnnotatedCluster =
        applyClusterTransformations nixosConfiguredCluster
        nixosConfiguredCluster.extensions.deploymentTransformations;

    in deploymentAnnotatedCluster;

}
