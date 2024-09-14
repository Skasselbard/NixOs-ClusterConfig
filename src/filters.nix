{ lib }:
with lib;
let

  pathTemplate = clusterName: machineName:
    "domain.clusters.${clusterName}.machines.${machineName}";

  filtersToPaths = filters: clusterName: config:
    lists.flatten (lists.forEach filters (filter: (filter clusterName config)));

in {

  # filter function that builds a resolvable path for a host
  hostname = hostName: clusterName: config:
    [ (pathTemplate clusterName hostName) ];

  clusterMachines = clusterName: config:
    let cluster = config.domain.clusters."${clusterName}";
    in lists.forEach (attrsets.attrNames cluster.machines)
    (machineName: (pathTemplate clusterName machineName));

  # resolves a filter function to the attribute it points to and returns its annotations 
  resolve = filter: clusterName: config:
    lists.flatten (lists.forEach (filtersToPaths filter clusterName config)
      (path:
        let
          resolvedElement = (attrsets.attrByPath (strings.splitString "." path)
            {
              # this is the default element if the path was not found
              # TODO: throw an error if the path cannot be found?
            } config);
        in resolvedElement.annotations));

  inherit filtersToPaths;
}
