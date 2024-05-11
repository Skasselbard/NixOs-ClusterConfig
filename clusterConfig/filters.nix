{ lib }:
with lib; {

  hostname = hostName: clusterName: config:
    [ "domain.clusters.${clusterName}.machines.${hostName}" ];

  toConfigAttrPaths = filters: clusterName: config:
    lists.flatten (lists.forEach filters (filter: (filter clusterName config)));

  resolve = paths: config:
    lists.flatten (lists.forEach paths (path:
      let
        resolvedElement = (attrsets.attrByPath (strings.splitString "." path) {
          # this is the default element if the path was not found
          # TODO: throw an error if the path cannot be found?
        } config);
      in resolvedElement.annotations));

}
