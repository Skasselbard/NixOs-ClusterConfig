{ lib, clusterlib, ... }:
config:
let
  clusters = config.domain.clusters;
  clusterNames = builtins.attrNames clusters;
  entries = lib.concatMap (
    clusterName:
    let
      cluster = clusters.${clusterName};
    in
    map (nodeName: {
      inherit clusterName nodeName;
      qualified = "${clusterName}-${nodeName}";
    }) (builtins.attrNames cluster.machines ++ builtins.attrNames cluster.vms)
  ) clusterNames;
  placements = lib.concatMap (
    clusterName:
    lib.mapAttrsToList (name: vm: {
      inherit name clusterName;
      host = clusterlib.get.vmHost vm.host config;
    }) clusters.${clusterName}.vms
  ) clusterNames;
  checkName =
    kind: name:
    if name == "this" || builtins.match "[A-Za-z0-9_][A-Za-z0-9_-]*" name == null then
      throw "clusterConfig: invalid ${kind} name '${name}': names must be non-empty, contain only letters, digits, '_' or '-', and cannot be 'this'"
    else
      true;

  # Tags and labels are shared vocabulary: selectors, documentation and (later)
  # Kubernetes labels consume them, so they are restricted to the characters
  # that stay valid in all of those contexts.
  labelValuePattern = "[A-Za-z0-9]([A-Za-z0-9._-]{0,61}[A-Za-z0-9])?";

  checkNodeMetadata =
    clusterName: nodeName: node:
    let
      check =
        kind: value:
        if builtins.match labelValuePattern value != null then
          true
        else
          throw "clusterConfig: invalid ${kind} '${value}' on node '${clusterName}.${nodeName}': it must match ${labelValuePattern}";
    in
    map (check "tag") (node.tags or [ ])
    ++ map (check "label key") (builtins.attrNames (node.labels or { }))
    ++ map (check "label value") (builtins.attrValues (node.labels or { }));

  metadataChecks = lib.concatMap (
    clusterName:
    let
      cluster = clusters.${clusterName};
    in
    lib.concatMap (nodeName: checkNodeMetadata clusterName nodeName cluster.machines.${nodeName}) (
      builtins.attrNames cluster.machines
    )
    ++ lib.concatMap (nodeName: checkNodeMetadata clusterName nodeName cluster.vms.${nodeName}) (
      builtins.attrNames (cluster.vms or { })
    )
  ) clusterNames;

  checks =
    map (name: checkName "cluster" name) clusterNames
    ++ map (
      entry:
      if !(checkName "node" entry.nodeName) then
        false
      else if
        clusters.${entry.clusterName}.machines ? ${entry.nodeName}
        && clusters.${entry.clusterName}.vms ? ${entry.nodeName}
      then
        throw "clusterConfig: node '${entry.nodeName}' in cluster '${entry.clusterName}' is defined as both a machine and a VM"
      else
        let
          matches = builtins.filter (other: other.qualified == entry.qualified) entries;
        in
        if builtins.length matches > 1 then
          throw "clusterConfig: qualified node name '${entry.qualified}' collides: ${
            lib.concatMapStringsSep ", " (x: "${x.clusterName}.${x.nodeName}") matches
          }"
        else
          true
    ) entries
    ++ map (
      vm:
      let
        matching = builtins.filter (other: other.name == vm.name && other.host == vm.host) placements;
      in
      if builtins.length matching > 1 then
        throw "clusterConfig: host '${vm.host.machine}.${vm.host.cluster}' has multiple VMs named '${vm.name}': ${
          lib.concatMapStringsSep ", " (x: "${x.clusterName}.${x.name}") matching
        }"
      else
        true
    ) placements;
  scopeConflicts =
    lib.concatMap
      (
        scope:
        let
          conflicts = builtins.filter (name: builtins.hasAttr name config.extensions.${scope}.packages) (
            builtins.attrNames config.extensions.nodes.packages
          );
        in
        if conflicts == [ ] then
          [ ]
        else
          [
            (throw "clusterConfig: conflicting ${scope} and node packages: ${lib.concatStringsSep ", " conflicts}")
          ]
      )
      [
        "machines"
        "vms"
      ];
in
builtins.deepSeq (checks ++ scopeConflicts ++ metadataChecks) config
