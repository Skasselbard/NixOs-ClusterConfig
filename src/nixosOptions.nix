{ lib, ... }:

let

  mkOption = lib.mkOption;

  anything = lib.types.anything;
  attrsOf = lib.types.attrsOf;
  listOf = lib.types.listOf;
  nullOr = lib.types.nullOr;
  raw = lib.types.raw;
  str = lib.types.str;
  submodule = lib.types.submodule;

  clusterType.options = {
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
      type = attrsOf anything; # TODO: maybe this can be type safe, although with minimal benefit because its auto generated
      default = { };
    };

    services = mkOption {
      description = ''
        The set of cluster services that are configured in the cluster config.

        The keys are the names of the services and the values are the service configurations.
      '';
      default = { };
      type = attrsOf anything;
      # type = attrsOf (submodule {
      #   options = {
      #     selectors = mkOption {
      #       description = "Annotations from the machines that are are added to the selectors of the cluster service in the cluster config";
      #       type = listOf annotation;
      #     };

      #     roles = mkOption {
      #       description = "Annotations from the machines that are are configured in the roles attribute of the cluster service config.";
      #       type = attrsOf (listOf annotation);
      #       default = { };
      #     };

      #   };
      # });

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
