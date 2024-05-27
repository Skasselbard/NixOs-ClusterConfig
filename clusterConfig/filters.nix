{ lib, clusterlib }:
with lib;
let

  pathTemplate = clusterName: machineName:
    "domain.clusters.${clusterName}.machines.${machineName}";
  get = clusterlib.get;

in {

  # filter function that builds a resolvable path for a host
  hostname = hostName: clusterName: config:
    [ (pathTemplate clusterName hostName) ];

  clusterMachines = clusterName: config:
    let cluster = config.domain.clusters."${clusterName}";
    in lists.forEach (attrsets.attrNames cluster.machines)
    (machineName: (pathTemplate clusterName machineName));

  # resolves a filter function to its 'annotation' attribute
  resolve = paths: config:
    lists.flatten (lists.forEach paths (path:
      let
        resolvedElement = (attrsets.attrByPath (strings.splitString "." path) {
          # this is the default element if the path was not found
          # TODO: throw an error if the path cannot be found?
        } config);
      in resolvedElement.annotations));

}
