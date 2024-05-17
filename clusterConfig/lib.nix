{ lib }:
with lib;
with lib.types;
let
  #############
  # Type stubs that can be extended

  domainType = { clusterType ? { options = { }; } }: {
    clusters = mkOption { type = attrsOf (submodule clusterType); };
  };

  clusterType = { # -
    usertype ? { options = { }; }, # -
    clusterServiceType ? { options = { }; }, # -
    machineType ? { options = { }; } }: {
      options = {
        users = mkOption { type = attrsOf (submodule usertype); };
        services = mkOption { type = attrsOf (submodule clusterServiceType); };
        machines = mkOption { type = attrsOf (submodule machineType); };
      };
    };

  machineType = { # -
    usertype ? { options = { }; }, # -
    virtualizationType ? { options = { }; } }: {
      options = {
        users = mkOption { type = attrsOf (submodule usertype); };

        virtualization =
          mkOption { type = attrsOf (submodule virtualizationType); };

      };
    };

  ############
  # helper functions

  forEachAttrIn = attrSet: function: (attrsets.mapAttrs function attrSet);

in { inherit domainType clusterType machineType forEachAttrIn; }
