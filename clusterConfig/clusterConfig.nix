{ pkgs }:
with pkgs.lib;
with pkgs.lib.types;
let

  domainType = {
    # build = mkOption {type = listOf derivation} TODO: maybe an internal attr that stores the system configs
    suffix = domainDefinitionType;
    clusters = mkOption {
      description = "A list of clusters";
      type = attrsOf (submodule clusterType);
      default = { };
    };
  };

  clusterType = {
    options = {
      services = mkOption {
        description = "A list of services deployed on the cluster nodes.";
        type = attrsOf (submodule clusterServiceType);
        default = { };
      };
      machines = mkOption {
        description =
          "A list of NixOS machines that will generate a NixOs system config.";
        type = attrsOf (submodule machineType);
        default = { };
      };
    };
  };

  clusterServiceType = {
    options = {
      selector = mkOption {
        description = mdDoc "TODO: describe the options";
        type = enum [ "default" "other" "unesed" ];
        default = "other";
      };
      roles = mkOption {
        description = mdDoc "TODO:";
        type = roleType;
        default = { };
      };
      config = mkOption {
        description = lib.mdDoc "Servicve specific config";
        type = attrsOf anything;
        default = { };
      };
    };
  };

  machineType = {
    options = {
      system = mkOption {
        description = lib.mdDoc "TODO:";
        type = nullOr str;
        default = null;
      };
      nixosModules = mkOption {
        description = lib.mdDoc "machine specific config";
        type = listOf anything;
        default = [ ];
      };
      # services = {};
      # interfaces TODO: query with a function??

      virtualization = mkOption {
        description =
          "A list of virtualizaion drivers that will generate a NixOs config that handles virtualization.";
        type = attrsOf (submodule virtualizationType);
        default = { };
      };

      # TODO: how would a generic virtualization interface look like
      # e.g. config -> [ (name = [ ip ]) ]

      # virtDriver = {
      #   functions = {
      #     getSelectors = {}:{};
      #     builcConfig = {}:{};
      #   };
      #   config = {  };
      # };

    };
  };

  virtualizationType = { };
  # functions = {
  #   getSelectors = {}:{};
  #   builcConfig = {}:{};
  # };
  # config = {  };

  roleType = attrsOf (either (selectorType) (listOf selectorType));

  selectorType = str;

  domainDefinitionType = mkOption {
    type = strMatching "[^.]+(\\.[^./\\r\\n ]+)*"; # TODO: Better domain regex?
  };

  functions = {
    get = {
      attrName = attr: (head (builtins.attrNames attr));

      Services.Selectors = cluster: cluster.services;
      machines = cluster: cluster.machines;
      clusters = config.domain.clusters;
    };
    build = {

      nixosConfigurations = config:
        attrsets.mapAttrs (machineName: machineConfig:
          (functions.build.nixosConfiguration { } {
            system = machineConfig.system;
            modules =
              (lists.optionals (builtins.hasAttr "nixosModules" machineConfig)
                machineConfig.nixosModules);
          })) (functions.build.machineSet config);

      # TODO: expand serviceConfigs to modules
      # TODO: maybe the service configs have to be added previously
      nixosConfiguration = serviceConfigs: machineConfig: {
        modules = machineConfig.modules;
      };

      # config -> {"machine1.cluster1.domainSuffix" = machine1Cluster1Definition; ... "machineN.clusterN.domainSuffix" = machineNClusterNDefinition;}
      # Reduces 'config.domain' to a set of named machineTypes.
      # The machine names are convertet to a domain name in the form of 'machineName.clusterName.domainSuffix'.
      machineSet = config:
        attrsets.mergeAttrsList (attrValues (attrsets.mapAttrs
          (clusterPath: clusterDefinition:
            (functions.build.machinePaths clusterPath clusterDefinition))
          (functions.build.clusterPaths config)));

      # config -> { cluster1DnsName = cluster1Definition; ... clusterNName = clusterNDefinition}
      # Reduces 'config.domain' to a set of named clusterTypes.
      # The cluster names are convertet to a domain name in the form of 'clusterName.domainSuffix'.
      clusterPaths = config:
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

  };

  evalCluster = clusterConfig:
    pkgs.lib.evalModules {
      modules = [
        (import ./options.nix { inherit pkgs; })
        { config = { domain = clusterConfig.domain; }; }
      ];
    };

in {

  nixosConfigurations = nixpkgs: clusterConfig:
    # pkgs.lib.attrsets.mapAttrs
    #   (machineName: machineConfig: pkgs.lib.nixosSystem machineConfig)
    let
      # evaluate cluster config to check for type consistency
      eval = (evalCluster clusterConfig);
    in attrsets.mapAttrs
    (machineName: machineConfig: nixpkgs.lib.nixosSystem machineConfig)
    (functions.build.nixosConfigurations clusterConfig);
}
