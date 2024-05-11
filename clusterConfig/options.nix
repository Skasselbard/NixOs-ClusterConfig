{ pkgs, colmena }:
with pkgs.lib;
with pkgs.lib.types;
let
  usertype = (import ./userOptions.nix { inherit pkgs; });

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
        type = attrsOf (submodule usertype);
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
        type = attrsOf (submodule usertype);
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

      deployment = let
        colmenaOptions = (import "${colmena.outPath}/src/nix/hive/options.nix");
      in attrsets.recursiveUpdate
      # import colmena deployment options
      (colmenaOptions.deploymentOptions {
        lib = pkgs.lib;
        name = "{hostname}";
      }).options.deployment
      # overwrite colmena defaults
      {
        # targetHost = TODO: ?; 
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

in { options = { domain = domainType; }; }
