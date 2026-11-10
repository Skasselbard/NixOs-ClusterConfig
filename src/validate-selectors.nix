{ lib, filters }:
config:
let
  checks = lib.concatMap (
    clusterName:
    let
      cluster = config.domain.clusters.${clusterName};
    in
    lib.concatMap (
      serviceName:
      let
        service = cluster.services.${serviceName};
        check =
          label: selectedFilters:
          map (
            path:
            let
              parts = lib.splitString "." path;
            in
            if
              builtins.length parts != 5
              || builtins.elemAt parts 0 != "domain"
              || builtins.elemAt parts 1 != "clusters"
              || builtins.elemAt parts 2 != clusterName
              || !(builtins.elem (builtins.elemAt parts 3) [
                "machines"
                "vms"
              ])
              || !(lib.hasAttrByPath parts config)
            then
              throw "clusterConfig: ${clusterName}.${serviceName} ${label} references invalid or non-local node '${path}'"
            else
              true
          ) (filters.filtersToPaths selectedFilters clusterName config);
      in
      [ (check "selectors" service.selectors) ]
      ++ lib.mapAttrsToList (name: role: check "role ${name}" role) service.roles
    ) (builtins.attrNames cluster.services)
  ) (builtins.attrNames config.domain.clusters);
in
builtins.deepSeq checks config
