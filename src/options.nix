{ lib, ... }:

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

  extensionType = {

    clusterTransformations = mkOption {
      description = ''
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
      description = ''
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
      description = ''
        A list of functions that takes a clusterConfig and returns a clusterConfig.

        These functions get called after the NixOsConfiguration evaluation.
        In this step, the cluster configuration can be annotated with additional scripts,
        based on the NixOsConfiguration from each machine.

        For example, in this step, the default clusterConfig workflow takes all machine configurations
        and adds deployment attributes, like a nixosConfigurations attribute that can be used in a flakes,
        to the configuration.
      '';
      type = listOf raw;
      default = [ ];
    };

    infoTransformations = mkOption {
      description = ''
        A list of functions that takes a clusterConfig and returns a clusterConfig.

        These functions get called after as a final evaluation.
        In this step, the generated flake can be extended with information attributes.
        These attributes should not alter the cluster configuration itself but only
        extract information.

        For example, in this step, the default clusterConfig workflow takes generates serializable
        cluster information that can be printed out.
      '';
      type = listOf raw;
      default = [ ];
    };

  };

  domainType = {
    suffix = domainDefinitionType;
    clusters = mkOption {
      description = "A list of clusters";
      type = attrsOf (submodule clusterType);
      default = { };
    };
  };

  clusterType = {
    options = {
      users = mkOption {
        description = "A list of users deployed on the cluster nodes.";
        type = attrsOf (submodule userType);
        default = { };
      };
      services = mkOption {
        description = "A list of services deployed on the cluster nodes."; # TODO: more details
        type = attrsOf (submodule clusterServiceType);
        default = { };
      };
      machines = mkOption {
        description = "A list of NixOS machines that will generate a NixOs system config.";
        type = attrsOf (submodule machineType);
        default = { };
      };
    };
  };

  clusterServiceType = {
    options = {
      selectors = mkOption {
        description = "A list of filters that resolve nixos machines"; # TODO: more details
        type = listOf filterType;
      };
      roles = mkOption {
        description = "TODO:";
        type = roleType;
        default = { };
      };
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
      };
      extraConfig = mkOption {
        description = ''
          Service extra configuration

          Additional Configuration in the form of a normal NixOs module.
        '';
        type = raw;
        default = { };
      };
    };
  };

  machineType = {
    options = {
      system = mkOption {
        description = lib."The type of system for this machine";
        example = "x86_64-linux";
        type = str;
      };

      users = mkOption {
        description = "A list of users deployed on the machine node in addition to the cluster users.";
        type = attrsOf (submodule userType);
        default = { };
        example = {
          bob = systemConfig {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
          };
        };
      };

      servicesAddresses = mkOption {
        description = "A list of attributes with service addresses (ip + port) for a service role and an additional config that is added to the nixosModules of the machine";
        type = listOf (submodule serviceAddressType);
        default = [ ];
        example = [

          clusterlib.ip.staticIpV4OpenUdp
          {
            ip = "192.168.1.10";
            role = "vault-api";
            interface = "eth0";
          }

        ];

      };

      nixosModules = mkOption {
        description = lib."machine specific config";
        type = listOf raw;
        default = [ ];
        example = {
          boot.loader.systemd-boot.enable = true;
        };
      };

      virtualization = mkOption {
        description = "A list of virtualizaion drivers that will generate a NixOs config that handles virtualization.";
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

  filterType = raw; # TODO:custom function type? https://nixos.org/manual/nixos/stable/#sec-option-types-custom

  domainDefinitionType = mkOption { type = fqdnString; };

  fqdnString = strMatching "[^.]+(\\.[^./\\r\\n ]+)*"; # TODO: Better domain regex?

in
{
  options = {
    extensions = extensionType;
    domain = domainType;
  };
}
