{
  clusterInfo,
  selectors,
  roles,
  this,
}:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  kubeLib = import ../kubelib.nix { inherit lib; };

  cfg = config.services.kubernetes.cluster;
  controlPlaneNodeList = kubeLib.getControlPlaneList roles;
  workerNodeList = kubeLib.getWorkerList roles;
  allNodes = controlPlaneNodeList ++ workerNodeList;

in
{
  apiVersion = "v1";
  kind = "NodeList";
  items =
    # build a Node object for each node in the cluster (control-plane + workers)
    lib.map (
      node:
      let
        nodeIsControlPlane = builtins.any (n: n.machineName == node.machineName) controlPlaneNodeList;
        nodeIsWorker = builtins.any (n: n.machineName == node.machineName) workerNodeList;
      in
      {
        apiVersion = "v1";
        kind = "Node";
        metadata = {
          name = node.fqdn;
          labels =
            # Official Kubernetes role label
            (lib.optionalAttrs nodeIsControlPlane {
              "node-role.kubernetes.io/control-plane" = "";
            })
            // (lib.optionalAttrs nodeIsWorker {
              "node-role.kubernetes.io/worker" = "";
            })
            // {
              # Declarative NixOS-specific labels (fall back to available attrs)
              "cluster.nixos.org/hostname" = node.machineName;
              "cluster.nixos.org/release" = node.nixos.release;
              "cluster.nixos.org/codename" = node.nixos.codeName;
              "cluster.nixos.org/kernel" = node.nixos.kernelVersion;

              # Give the kubernetes addon manager the ability to manage this resource
              "addonmanager.kubernetes.io/mode" = "Reconcile";
            };
        };
      }
    ) allNodes;
}
