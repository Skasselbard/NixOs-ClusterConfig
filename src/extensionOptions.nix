{ lib, ... }:

let

  mkOption = lib.mkOption;

  attrsOf = lib.types.attrsOf;
  listOf = lib.types.listOf;
  nullOr = lib.types.nullOr;
  optionType = lib.types.optionType;
  port = lib.types.port;
  raw = lib.types.raw;
  anything = lib.types.anything;
  str = lib.types.str;
  strMatching = lib.types.strMatching;
  submodule = lib.types.submodule;

  scriptType = raw;

  extensionType = {

    cluster = {

      options = mkOption {
        description = ''
          A set of options that are added to the cluster-config options.
          These can be used in cluster config scripts and are added to the cluster annotations
        '';
        default = { };

        type = attrsOf anything;
      };

      scripts = mkOption {
        description = ''
          A set of scripts that will be made available to the cluster scripts.
          TODO: closure of type {args}: str.
          args = TODO:;
        '';
        type = attrsOf scriptType;
        default = { };
      };

    };

    clusterMachine = {

      options = mkOption {
        description = ''
          A set of options that are added to the cluster-config-machine-options.
          These can be used in cluster config scripts and are added to the machine annotations
        '';
        default = { };

        type = attrsOf anything;
      };

      scripts = mkOption {
        description = ''
          A set of scripts that will be made available to the cluster scripts.
          TODO: closure of type {args}: str.
          args = TODO:;
        '';
        type = attrsOf scriptType;
        default = { };
      };

      # TODO: package

    };

    clusterServices = mkOption {
      description = ''
        A set of cluster services that should be enabled in the cluster.

        The keys are the names of the services and the values are the service configurations.
      '';
      type = attrsOf (submodule {
        options = {

          defaultModule = mkOption {
            description = ''
              The root NixOs module of the service.
            '';
            type = raw;
          };

          roles = mkOption {
            description = ''
              A set of role names a machine can be assigned to.
              The service config can depend on the role(s) of a machine so that the service configuration can be adapted accordingly
            '';
            type = listOf str;
            default = [ ];
          };

          options = mkOption {
            description = ''
              A set of options that can be used e.g. to give service scripts additional information.
            '';
            default = { };
            type = attrsOf anything;
          };

          scripts = mkOption {
            description = ''
              A set of scripts that will be made available to the cluster scripts.
              TODO: closure of type {args}: str.
              args = TODO:;
            '';
            type = attrsOf scriptType;
            default = { };
          };

        };
      });
      default = { };

    };
    transformations = {

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
  };

in
{
  options = {
    extensions = extensionType;
  };
  config = {

  };
}
