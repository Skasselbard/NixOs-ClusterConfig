{
  config, # unevaluated Cluster Config (its the user defined one, not the one added to config.clusterConfig during evaluation)
  clusterlib,
}:

{ lib, ... }:

let

  mkOption = lib.mkOption;

  attrsOf = lib.types.attrsOf;
  listOf = lib.types.listOf;
  nullOr = lib.types.nullOr;
  port = lib.types.port;
  raw = lib.types.raw;
  str = lib.types.str;
  submodule = lib.types.submodule;

  forEach = lib.lists.forEach;
  forEachAttrIn = clusterlib.forEachAttrIn;
  listToAttrs = builtins.listToAttrs;

  clusterType.options = config.extensions.cluster.options // {
    fqdn = mkOption {
      description = "The fully qualified domain name of the cluster.";
      type = str;
      example = "example.com";
      default = "";
    };

    machines = mkOption {
      description = ''
        A list of machines that are part of the cluster with their cluster config level configuration.
        A machine called "this" will be included to the list of the "this" cluster.
        This will point to the current machine that is evaluated by Cluster Config.
      '';
      type = attrsOf (submodule machineType);
      default = { };
    };

    services = forEachAttrIn config.extensions.clusterServices (
      serviceName: serviceDefinition:

      serviceDefinition.options
      // {
        selectors = mkOption {
          description = "A list of resolved nixos machines"; # TODO: more details
          type = listOf (submodule machineType);
        };

        roles = listToAttrs (
          forEach serviceDefinition.roles (roleName: {
            name = roleName;
            value = mkOption {
              description = "TODO:";
              type = listOf (submodule machineType);
              default = [ ];
            };
          })
        );

      }
    );
  };

  machineType.options = config.extensions.clusterMachine.options // {

    config = mkOption {
      description = ''
        The evaluated nixos configuration for this machine.
      '';
      type = raw;
    };

    fqdn = mkOption {
      description = "The fully qualified domain name of the machine. Automatically populated from the cluster configuration.";
      type = str;
      example = "node1.example.com";
    };

    ips = mkOption {
      description = "A list of ip addresses assigned to the machine. Automatically populated with static ip addresses from the networking configuration.";
      type = attrsOf raw;
      default = { };
    };

    name = mkOption {
      description = "The name of the machine within the cluster. Automatically populated from the attribute name in the machines definition.";
      type = str;
      example = "node1";
    };

    services = mkOption {
      description = "A list of service names this machine was selected for.";
      type = listOf str;
      example = [
        "kubernetes"
        "vault"
      ];
      default = [ ];
    };

    serviceAddresses = mkOption {
      description = "A list of attributes with service addresses (ip + port) for a service role and an additional config that is added to the nixosModules of the machine";
      type = listOf (submodule {
        options = {

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
      });
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

    system = mkOption {
      description = lib."The type of system for this machine";
      example = "x86_64-linux";
      type = str;
    };

  };
in
{
  options.clusterConfig = {
    suffix = mkOption {
      type = str;
      default = "";
    };
    clusters = mkOption {
      description = ''
        A list of clusters declared in the Cluster Config.
        A cluster called "this" will be included to the list.
        This will point to the cluster the current machine is associated with.
      '';
      type = attrsOf (submodule clusterType);
      default = { };
    };
  };
}
