{ nixpkgs, nixos-generators, home-manager, colmena, flake-utils, nixos-anywhere
}:
let # imports
  pkgs = import nixpkgs {
    # the exact value of 'system' should be unimportant since we only use lib
    system = "x86_64-linux";
  };
  clusterlib = import ./lib.nix {
    inherit nixpkgs;
    lib = pkgs.lib;
  };

  filters = import ./filters.nix { lib = pkgs.lib; };
  add = clusterlib.add;

in with pkgs.lib;
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

  evalCluster = clusterConfig:
    evalModules {
      modules = [
        ./deployment.nix
        ./transformations.nix
        ./options.nix
        {
          imports = clusterConfig.imports;
          config = {
            # make flake functions from nixpkgs available for submodules
            _module.args = {
              inherit pkgs nixpkgs clusterlib colmena flake-utils;
              lib = pkgs.lib;
            };
            # set the domain attribute for evaluation
            domain = clusterConfig.domain;
          };
        }
      ];
    };

  evalMachines = config: add.nixosConfigurations config;

  machineAnnotation = config:
    add.machineConfiguration config (clusterName: machineName: machineConfig: {
      annotations = {
        inherit clusterName machineName;
        ips = get.ips machineConfig.nixosConfiguration;
        fqdn = machineConfig.nixosConfiguration.config.networking.fqdn;
        # TODO: subnets?
      };
    });

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
  # cluster users
  # - define a set of users that will be deployed on all machines in the cluster (like services)
  # maybe the same with groups

  # a function that builds and evaluates the clusterconfig to apply directly on the cluster definition
  buildCluster = config:
    let
      # Step 1:
      # Evaluate the cluster to check for type conformity
      evaluatedCluster = (evalCluster config).config;

      # Step 2:
      clusterAnnotatedCluster = applyClusterTransformations evaluatedCluster
        evaluatedCluster.extensions.clusterTransformations;

      # Step 3:
      # Evaluate the nixosModules from all machines to generate a first NixosConfiguration.
      # This config will be overwritten later.
      machineEvaluatedCluster = evalMachines clusterAnnotatedCluster;

      # Step 4:
      # Annotate the cluster with data from the machine configurations
      # This includes:
      # - the used IP addresses
      # - the FQDN
      evalAnnotatedCluser = machineAnnotation machineEvaluatedCluster;

      # Step 5:
      serviceAnnotatedCluster = applyClusterTransformations evalAnnotatedCluser
        evalAnnotatedCluser.extensions.moduleTransformations;

      # Step 6:
      # Evaluate the final NixosConfigurations that can be added as build targets
      nixosConfiguredCluster = evalMachines serviceAnnotatedCluster;

      # Step 7:
      deploymentAnnotatedCluster =
        applyClusterTransformations nixosConfiguredCluster
        nixosConfiguredCluster.extensions.deploymentTransformations;

    in deploymentAnnotatedCluster;

}
