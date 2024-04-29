{ pkgs }:
with pkgs.lib;
let

  optionals = {
    nixosModules = machineConfig:
      (lists.optionals (builtins.hasAttr "nixosModules" machineConfig)
        machineConfig.nixosModules);
  };

  get = {
    attrName = attr: (head (builtins.attrNames attr));

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

    Services.Selectors = cluster: cluster.services;
    machines = cluster: cluster.machines;
    clusters = config.domain.clusters;
  };
  add = {
    # returns a the given 'machineConfig' updated with the module(s) given in 'nixosModules
    nixosModules = nixosModules: machineConfig:
      machineConfig // {
        nixosModules = lists.flatten
          ([ nixosModules ] ++ (optionals.nixosModules machineConfig));
      };

    hostnames = config: # root of a cluster configuration
      {
        domain = config.domain // {
          clusters = (attrsets.mapAttrs (clusterName: clusterConfig:
            attrsets.mapAttrs (machineName: machineConfig:
              (add.nixosModules { networking.hostName = machineName; }
                machineConfig)) clusterConfig.machines) config.domain.clusters);
        };
      };

    # Add 'configAttr' at 'selector' to 'config' and return the updated config.
    # configuration = { configAttr, selector }: config: { TODO: };
  };
  build = {

    nixosConfigurations = config: # root of a cluster configuration
      attrsets.mapAttrs (machineName: machineConfig:
        (build.nixosConfiguration { } {
          system = machineConfig.system;
          modules = (optionals.nixosModules machineConfig);
        })) (build.machineSet config);

    # TODO: expand serviceConfigs to modules
    # TODO: maybe the service configs have to be added previously
    nixosConfiguration = serviceConfigs: machineConfig: {
      modules = machineConfig.modules;
    };

    # config -> {"machine1.cluster1.domainSuffix" = machine1Cluster1Definition; ... "machineN.clusterN.domainSuffix" = machineNClusterNDefinition;}
    # Reduces 'config.domain' to a set of named machineTypes.
    # The machine names are convertet to a domain name in the form of 'machineName.clusterName.domainSuffix'.
    machineSet = config: # root of a cluster configuration
      attrsets.mergeAttrsList (attrValues (attrsets.mapAttrs
        (clusterPath: clusterDefinition:
          (build.machinePaths clusterPath clusterDefinition))
        (build.clusterPaths config)));

    # config -> { "cluster1.domainSuffix" = cluster1Definition; ... "clusterN.domainSuffix" = clusterNDefinition}
    # Reduces 'config.domain' to a set of named clusterTypes.
    # The cluster names are convertet to a domain name in the form of 'clusterName.domainSuffix'.
    clusterPaths = config: # root of a cluster configuration
      attrsets.mapAttrs' (clusterName: clusterDefinition:
        nameValuePair (clusterName + "." + config.domain.suffix)
        clusterDefinition) config.domain.clusters;

    # clusterPath: clusterDefinition: -> {machine1DnsName = machine1Definition; ... machineNName = MachineNDefinition;}
    # Returns a set of named machines given a (cluster-) name and a clusterType.
    # The machine names are convertet to a domain name in the form of 'machineName.clusterName.domainSuffix'.
    machinePaths = clusterPath: clusterDefinition:
      attrsets.mapAttrs' (machineName: machineDefinition:
        nameValuePair (machineName + "." + clusterPath) machineDefinition)
      clusterDefinition.machines;
  };

  evalCluster = clusterConfig:
    pkgs.lib.evalModules {
      modules = [
        (import ./options.nix { inherit pkgs; })
        { config = { domain = clusterConfig.domain; }; }
      ];
    };

  ipSites = [ "interfaces" "vlans" "macvlans" ];
in {

  # TODOs:
  # automatically set hostname
  # automatically set networking.domain
  # conditionally include virtual interfaces
  # include dhcp hints for static dhcp ips

  nixosConfigurations = nixpkgs: clusterConfig:
    let
      # evaluate cluster config to check for type consistency
      eval = (evalCluster clusterConfig);
    in attrsets.mapAttrs
    (machineName: machineConfig: nixpkgs.lib.nixosSystem machineConfig)
    (build.nixosConfigurations clusterConfig);

  ips = machineConfig:
    lists.forEach (get.interface.definitions machineConfig) (interface:
      let
        interfaceName = (head (attrsets.attrNames interface));
        interfaceValue = (head (attrsets.attrValues interface));
      in { "${interfaceName}" = get.interface.ips interfaceValue; });

  hostnames = add.hostnames;
}
