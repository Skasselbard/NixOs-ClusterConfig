{ lib, ... }:

let

  mkOption = lib.mkOption;

  attrsOf = lib.types.attrsOf;
  listOf = lib.types.listOf;
  nullOr = lib.types.nullOr;
  optionType = lib.types.optionType;
  port = lib.types.port;
  raw = lib.types.raw;
  str = lib.types.str;
  strMatching = lib.types.strMatching;
  submodule = lib.types.submodule;

  annotation = attrsOf raw;

in
{
  options.cluster.services = mkOption {
    description = ''
      The set of cluster services that are configured in the cluster config.

      The keys are the names of the services and the values are the service configurations.
    '';
    default = { };
    type = attrsOf (submodule {
      options = {
        selectors = mkOption {
          description = "Annotations from the machines that are are added to the selectors of the cluster service in the cluster config";
          type = listOf annotation;
        };

        roles = mkOption {
          description = "Annotations from the machines that are are configured in the roles attribute of the cluster service config.";
          type = attrsOf (listOf annotation);
          default = { };
        };

        clusterInfo = mkOption {
          description = "Information about the cluster the service is running in.";
          type = raw;
        };

        this = mkOption {
          description = "Annotations from the machine that is associated with the currently evaluated config.";
          type = raw;
        };
      };
    });

  };

}
