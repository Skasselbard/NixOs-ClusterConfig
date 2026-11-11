{ lib }:
with lib;
let

  pathTemplate = clusterName: machineName: "domain.clusters.${clusterName}.machines.${machineName}";

  vmPathTemplate = clusterName: vmName: "domain.clusters.${clusterName}.vms.${vmName}";

  filtersToPaths =
    filters: clusterName: config:
    # A list of filters is a union. Nodes matched by several filters are only
    # returned once, keeping the order of the first mention.
    lists.unique (lists.flatten (lists.forEach filters (filter: (filter clusterName config))));

  # Tags and labels may be given as a single value or as a set that has to match
  # in part (any) or completely (all). An empty set cannot match for the
  # intended purpose and is almost always a mistake, so it is rejected.
  tagList =
    name: tags:
    if builtins.isList tags then
      (
        if tags == [ ] then
          throw "clusterConfig: ${name} filter requires at least one tag"
        else
          tags
      )
    else if builtins.isString tags then
      [ tags ]
    else
      throw "clusterConfig: ${name} filter expects a tag or a list of tags";

  labelKeys =
    name: labels:
    if !(builtins.isAttrs labels) then
      throw "clusterConfig: ${name} filter expects a set of label values"
    else if labels == { } then
      throw "clusterConfig: ${name} filter requires at least one label"
    else
      builtins.attrNames labels;

  # Paths of all nodes (machines and VMs) of a cluster whose definition
  # satisfies `predicate name node`. Tags, labels and options are read from the
  # declared cluster config, so filters built on this work in every pipeline
  # stage.
  nodePathsWhere =
    predicate: clusterName: config:
    let
      cluster = config.domain.clusters."${clusterName}";
      matching =
        nodes: attrsets.attrNames (attrsets.filterAttrs (name: node: predicate name node) nodes);
    in
    lists.forEach (matching cluster.machines) (name: pathTemplate clusterName name)
    ++ lists.forEach (matching (cluster.vms or { })) (name: vmPathTemplate clusterName name);

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

  # ── Metadata filters (tags, labels and node options) ──

  # Select all nodes that carry at least one of the given tags.
  #
  # `tags` is either a single tag or a list of tags:
  #   tagsAny "prod"                  one tag
  #   tagsAny [ "prod" "gpu" ]        at least one of them
  tagsAny =
    tags: clusterName: config:
    let
      wanted = tagList "tagsAny" tags;
    in
    nodePathsWhere (_name: node: builtins.any (tag: builtins.elem tag (node.tags or [ ])) wanted) clusterName config;

  # Select all nodes that carry every given tag.
  #
  # `tags` is either a single tag or a list of tags:
  #   tagsAll "prod"                  one tag (same as tagsAny "prod")
  #   tagsAll [ "prod" "gpu" ]        every one of them
  tagsAll =
    tags: clusterName: config:
    let
      wanted = tagList "tagsAll" tags;
    in
    nodePathsWhere (_name: node: builtins.all (tag: builtins.elem tag (node.tags or [ ])) wanted) clusterName config;

  # Select all nodes where at least one of the given label pairs matches.
  #
  #   labelsAny { tier = "edge"; zone = "eu-west-1a"; }
  labelsAny =
    labels: clusterName: config:
    let
      keys = labelKeys "labelsAny" labels;
    in
    nodePathsWhere
      (_name: node: builtins.any (key: ((node.labels or { }).${key} or null) == labels.${key}) keys)
      clusterName
      config;

  # Select all nodes where every given label pair matches.
  #
  #   labelsAll { tier = "edge"; zone = "eu-west-1a"; }
  labelsAll =
    labels: clusterName: config:
    let
      keys = labelKeys "labelsAll" labels;
    in
    nodePathsWhere
      (_name: node: builtins.all (key: ((node.labels or { }).${key} or null) == labels.${key}) keys)
      clusterName
      config;

  # Select all nodes that declare the given label key, whatever its value.
  hasLabel =
    key: clusterName: config:
    nodePathsWhere (_name: node: (node.labels or { }) ? ${key}) clusterName config;

  # Select all nodes where the declared node option at `path` has the given
  # value, e.g. `nodeOption [ "deployment" "formatScript" ] "disko"`.
  #
  # Only plain values can be compared: functions and derivations are rejected
  # by Nix's equality operator, so query leaf options.
  nodeOption =
    path: value: clusterName: config:
    nodePathsWhere
      (
        name: node:
        if !(attrsets.hasAttrByPath path node) then
          throw "clusterConfig: nodeOption filter references '${lib.concatStringsSep "." path}', which is not set on node '${clusterName}.${name}'"
        else
          attrsets.getAttrFromPath path node == value
      )
      clusterName
      config;

  # Select all nodes where the evaluated NixOS option at `path` has the given
  # value, e.g. `machineOption [ "networking" "hostName" ] "web1"`.
  #
  # This reads the node's `nixosConfiguration`, which exists from the first node
  # evaluation onward. Service selectors are resolved after that evaluation, so
  # they can use it. The configuration is the first-pass one: options that
  # service modules or the injected `clusterConfig` add are not part of it yet.
  #
  # Cost: forcing the configuration evaluates the module system scaffolding and
  # then only the attribute path that is queried, not the whole configuration.
  # Because every node of the cluster is inspected, this adds a per-node
  # evaluation cost that `nodeOption` does not have.
  machineOption =
    path: value: clusterName: config:
    nodePathsWhere
      (
        name: node:
        let
          machineConfig =
            if node ? nixosConfiguration then
              node.nixosConfiguration.config
            else
              throw "clusterConfig: machineOption filter on node '${clusterName}.${name}' requires an evaluated machine configuration, which does not exist at this stage (machine options are available from the first node evaluation onward)";
        in
        if !(attrsets.hasAttrByPath path machineConfig) then
          throw "clusterConfig: machineOption filter references '${lib.concatStringsSep "." path}', which is not set on node '${clusterName}.${name}'"
        else
          attrsets.getAttrFromPath path machineConfig == value
      )
      clusterName
      config;

  # resolves a filter function to the attribute it points to and returns its annotations
  resolve =
    filter: clusterName: config:
    lists.flatten (
      lists.forEach (filtersToPaths filter clusterName config) (
        path:
        let
          parts = strings.splitString "." path;
          resolvedElement = if attrsets.hasAttrByPath parts config then
            attrsets.getAttrFromPath parts config
          else throw "clusterConfig: filter references missing path '${path}'";
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
        let parts = strings.splitString "." path;
        in if attrsets.hasAttrByPath parts config then attrsets.getAttrFromPath parts config
        else throw "clusterConfig: filter references missing path '${path}'"
      )
    );

  inherit filtersToPaths;
}
