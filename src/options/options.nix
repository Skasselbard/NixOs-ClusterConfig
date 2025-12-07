{
  config,
  lib,
  clusterlib,
  ...
}:

let

  mkOption = lib.mkOption;

  attrsOf = lib.types.attrsOf;
  listOf = lib.types.listOf;
  nullOr = lib.types.nullOr;
  port = lib.types.port;
  raw = lib.types.raw;
  str = lib.types.str;
  strMatching = lib.types.strMatching;
  submodule = lib.types.submodule;

  forEach = lib.lists.forEach;
  forEachAttrIn = clusterlib.forEachAttrIn;
  listToAttrs = builtins.listToAttrs;

  domainType = {
    suffix = domainDefinitionType;
    clusters = mkOption {
      description = "A list of clusters";
      type = attrsOf (submodule clusterType);
      default = { };
    };
  };

  clusterType = {
    options = config.extensions.cluster.options // {
      users = mkOption {
        description = "A list of users deployed on the cluster nodes.";
        type = attrsOf (submodule userType);
        default = { };
      };
      services = forEachAttrIn config.extensions.clusterServices (
        serviceName: serviceDefinition:

        serviceDefinition.options
        // {
          selectors = mkOption {
            description = "A list of filters that resolve nixos machines"; # TODO: more details
            type = listOf filterType;
          };

          roles = listToAttrs (
            forEach serviceDefinition.roles (roleName: {
              name = roleName;
              value = mkOption {
                description = "TODO:";
                type = listOf filterType;
                default = [ ];
              };
            })
          );

          definition = mkOption {
            description = ''
              Service definition

              Has to be closure in the form 
              { selectors, roles, this }:{
                # configuration
              }

              TODO:
            '';
            type = raw;
            default = serviceDefinition.defaultModule;
          };

          extraConfig = mkOption {
            description = ''
              Service extra configuration

              Additional Configuration in the form of a NixOs module.
            '';
            type = raw;
            default = { };
          };
        }
      );

      machines = mkOption {
        description = "A list of NixOS machines that will generate a NixOs system config.";
        type = attrsOf (submodule machineType);
        default = { };
      };
    };
  };

  machineType.options = config.extensions.clusterMachine.options // {

    system = mkOption {
      description = lib."The type of system for this machine";
      example = "x86_64-linux";
      type = str;
    };

    users = mkOption {
      description = "A list of users deployed on the machine node in addition to the cluster users.";
      type = attrsOf (submodule userType);
      default = { };
      example = ''
        {
          bob = systemConfig {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
          };
        }'';
    };

    serviceAddresses = mkOption {
      description = "A list of attributes with service addresses (ip + port) for a service role and an additional config that is added to the nixosModules of the machine";
      type = listOf (submodule serviceAddressType);
      default = [ ];
      example = ''
        [
          clusterlib.ip.staticIpV4OpenUdp
          {
            ip = "192.168.1.10";
            role = "vault-api";
            interface = "eth0";
          }
        ]'';

    };

    nixosModules = mkOption {
      description = lib."machine specific config";
      type = listOf raw;
      default = [ ];
      example = [{
        boot.loader.systemd-boot.enable = true;
      }];
    };

    # virtualization = mkOption {
    #   description = "A list of virtualizaion drivers that will generate a NixOs config that handles virtualization.";
    #   type = attrsOf (submodule virtualizationType);
    #   default = { };
    # };

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

  serviceAddressType.options = {

    tag = {

      role = mkOption {
        description = ''
          The role as known by the service. Only service known roles can be processed.
        '';
        type = str;
      };

      address = mkOption {
        description = ''
          An ip address used to expose the service.
        '';
        type = str; # TODO: use ip regex
      };

      port = mkOption {
        description = ''
          The port on witch to listen by the service.
        '';
        type = nullOr port;
        default = null;
      };

    };

    config = mkOption {
      description = ''
        A config attribute that is added to the nixosModules of the machine.
      '';
      type = raw;
    };

  };

  userType.options = {

    systemConfig = mkOption {
      description = ''
        An attribute containing NixOs options defined for 'config.users.users.''${name}.

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

  filterType = raw; # TODO:custom function type? https://nixos.org/manual/nixos/stable/#sec-option-types-custom

  domainDefinitionType = mkOption { type = fqdnString; };

  fqdnString = strMatching "[^.]+(\\.[^./\\r\\n ]+)*"; # TODO: Better domain regex?

in
{
  options = {
    domain = domainType;
  };
}
