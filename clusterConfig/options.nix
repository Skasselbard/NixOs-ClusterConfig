{ pkgs, ... }:
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
      nixosModules = mkOption {
        description = lib.mdDoc "machine specific config";
        type = listOf raw;
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

  roleType = attrsOf (listOf filterType);

  filterType =
    raw; # TODO:custom function type? https://nixos.org/manual/nixos/stable/#sec-option-types-custom

  domainDefinitionType = mkOption { type = fqdnString; };

  fqdnString =
    strMatching "[^.]+(\\.[^./\\r\\n ]+)*"; # TODO: Better domain regex?

in { options = { domain = domainType; }; }
