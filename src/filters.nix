{ lib }:
with lib;
let

  pathTemplate = clusterName: machineName: "domain.clusters.${clusterName}.machines.${machineName}";

  vmPathTemplate = clusterName: vmName: "domain.clusters.${clusterName}.vms.${vmName}";

  filtersToPaths =
    filters: clusterName: config:
    lists.flatten (lists.forEach filters (filter: (filter clusterName config)));

in
{

  # filter function that builds a resolvable path for a host
  hostname = hostName: clusterName: config: [ (pathTemplate clusterName hostName) ]; # legacy name
  machineName = hostName: clusterName: config: [ (pathTemplate clusterName hostName) ];


  clusterMachines =
    clusterName: config:
    let
      cluster = config.domain.clusters."${clusterName}";
    in
    lists.forEach (attrsets.attrNames cluster.machines) (
      machineName: (pathTemplate clusterName machineName)
    );

  # ── VM-specific filters ──

  # Select a specific VM by name
  vmName = vmName: clusterName: config: [ (vmPathTemplate clusterName vmName) ];

  # Select all VMs in a cluster
  clusterVms =
    clusterName: config:
    let
      cluster = config.domain.clusters."${clusterName}";
    in
    lists.forEach (attrsets.attrNames (cluster.vms or { })) (
      vmName: (vmPathTemplate clusterName vmName)
    );

  # Select all Nodes (machines and VMs) in a cluster
  clusterNodes =
  clusterName: config:
  let
    cluster = config.domain.clusters."${clusterName}";
    machinePaths = lists.forEach (attrsets.attrNames cluster.machines) (
      machineName: (pathTemplate clusterName machineName)
    );
    vmPaths = lists.forEach (attrsets.attrNames (cluster.vms or { })) (
      vmName: (vmPathTemplate clusterName vmName)
    );
  in
  machinePaths ++ vmPaths;

  # resolves a filter function to the attribute it points to and returns its annotations
  resolve =
    filter: clusterName: config:
    lists.flatten (
      lists.forEach (filtersToPaths filter clusterName config) (
        path:
        let
          resolvedElement = (
            attrsets.attrByPath (strings.splitString "." path) {
              # this is the default element if the path was not found
              # TODO: throw an error if the path cannot be found?
            } config
          );
        in
        resolvedElement
      )
    );

  # Resolves a filter function to a machine name
  # throws an error if the path does not match a machine path
  resolveMachineName =
    filter: clusterName: clusterConfig:
    lists.flatten (
      lists.forEach (filtersToPaths filter clusterName clusterConfig) (
        path:
        let
          reversedPathSegments = lists.reverseList (strings.splitString "." path);
        in
        if lists.head (lists.tail reversedPathSegments) != "machines" then
          throw "Error: tried to resolve a machine from a filter that does not filter (only) machines"
        else
          lists.head reversedPathSegments
      )
    );

  # Resolves a filter function to a VM name
  # throws an error if the path does not match a VM path
  resolveVmName =
    filter: clusterName: clusterConfig:
    lists.flatten (
      lists.forEach (filtersToPaths filter clusterName clusterConfig) (
        path:
        let
          reversedPathSegments = lists.reverseList (strings.splitString "." path);
        in
        if lists.head (lists.tail reversedPathSegments) != "vms" then
          throw "Error: tried to resolve a VM from a filter that does not filter (only) VMs"
        else
          lists.head reversedPathSegments
      )
    );

  # Resolves a filter function to a Node name (either vm or machine)
  # throws an error if the path does not match a machine or VM path
  resolveNodeName =
    filter: clusterName: clusterConfig:
    lists.flatten (
      lists.forEach (filtersToPaths filter clusterName clusterConfig) (
        path:
        let
          reversedPathSegments = lists.reverseList (strings.splitString "." path);
        in
        if
          lists.head (lists.tail reversedPathSegments) != "machines"
          && lists.head (lists.tail reversedPathSegments) != "vms"
        then
          throw "Error: tried to resolve a Node from a filter that does not filter (only) machines or VMs"
        else
          lists.head reversedPathSegments
      )
    );

  # resolves a filter function to the attribute it points to and returns the complete definition
  resolveDefinitions =
    filter: clusterName: config:
    lists.flatten (
      lists.forEach (filtersToPaths filter clusterName config) (
        path:
        (attrsets.attrByPath (strings.splitString "." path) {
          # this is the default element if the path was not found
          # TODO: throw an error if the path cannot be found?
        } config)
      )
    );

  inherit filtersToPaths;
}
