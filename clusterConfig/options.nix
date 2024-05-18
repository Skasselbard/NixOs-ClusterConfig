{ pkgs, ... }:
with pkgs.lib;
with pkgs.lib.types;
let

  extensionType = {

    clusterTransformations = mkOption {
      description = lib.mdDoc ''
        A list of functions that takes a clusterConfig and returns a clusterConfig.

        These functions get called after the first cluster evaluation.
        In this step, information declared in the cluster options can be transformed and used for annotations.
        The machine NixOsModules are unevaluated at this point.

        For example, in this step, the default clusterConfig workflow takes the names of all defined machines
        and sets the ``networking.hostname`` option for each machine.
      '';
      type = listOf raw;
      default = [ ];
    };

    moduleTransformations = mkOption {
      description = lib.mdDoc ''
        A list of functions that takes a clusterConfig and returns a clusterConfig.

        These functions get called after the NixOsConfiguration for each machine was evaluated for the first time
        and the networking annotations (ips and fqdns) where set.
        In this step, cluster and machine information can be used to modify the cluster config.
        After this step, the NixOsModules for each machine will be evaluated once again.

        For example, in this step, the default clusterConfig workflow takes the service and user configuration
        from the cluster and adds them to the nixOsModules of each machine.
      '';
      type = listOf raw;
      default = [ ];
    };

    deploymentTransformations = mkOption {
      description = lib.mdDoc ''
        A list of functions that takes a clusterConfig and returns a clusterConfig.

        These functions get called after the final NixOsConfiguration evaluation.
        In this step, the cluster configuration can be annotated with additional information,
        based on the NixOsConfiguration from each machine.

        For example, in this step, the default clusterConfig workflow takes all machine configurations
        and adds deployment attributes, like a nixosConfigurations attribute that can be used in a flakes,
        to the configuration.
      '';
      type = listOf raw;
      default = [ ];
    };

  };

  domainType = {
    suffix = domainDefinitionType;
    clusters = mkOption {
      description = mdDoc "A list of clusters";
      type = attrsOf (submodule clusterType);
      default = { };
    };
  };

  clusterType = {
    options = {
      users = mkOption {
        description = mdDoc "A list of users deployed on the cluster nodes.";
        type = attrsOf (submodule userType);
        default = { };
      };
      services = mkOption {
        description = mdDoc "A list of services deployed on the cluster nodes.";
        type = attrsOf (submodule clusterServiceType);
        default = { };
      };
      machines = mkOption {
        description = mdDoc
          "A list of NixOS machines that will generate a NixOs system config.";
        type = attrsOf (submodule machineType);
        default = { };
      };
    };
  };

  clusterServiceType = {
    options = {
      selectors = mkOption {
        description = mdDoc "TODO: describe the options";
        type = listOf filterType;
        default = [ ];
      };
      roles = mkOption {
        description = mdDoc "TODO:";
        type = roleType;
        default = { };
      };
      config = mkOption {
        description = lib.mdDoc "Servicve specific config";
        type = raw; # TODO: is a type necessary (or useful) here?
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

      users = mkOption {
        description = mdDoc
          "A list of users deployed on the machine node in addition to the cluster users.";
        type = attrsOf (submodule userType);
        default = { };
      };

      nixosModules = mkOption {
        description = lib.mdDoc "machine specific config";
        type = listOf raw;
        default = [ ];
      };

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

  userType.options = {

    systemConfig = mkOption {
      description = ''
        An attribute containing NixOs options defined for 'config.users.users.\${name}.

        This configuration is copied to the corresponding user for each machine in the cluster.
      '';
      type = attrsOf raw;
      default = { };
      example = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
      };
    };

  };

  virtualizationType = { };
  roleType = attrsOf (listOf filterType);

  filterType =
    raw; # TODO:custom function type? https://nixos.org/manual/nixos/stable/#sec-option-types-custom

  domainDefinitionType = mkOption { type = fqdnString; };

  fqdnString =
    strMatching "[^.]+(\\.[^./\\r\\n ]+)*"; # TODO: Better domain regex?

in {
  options = {
    extensions = extensionType;
    domain = domainType;
  };
}
