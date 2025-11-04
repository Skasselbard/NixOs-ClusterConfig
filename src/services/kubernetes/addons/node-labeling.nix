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
  etcdNodeList = kubeLib.getEtcdList roles;
  workerNodeList = kubeLib.getWorkerList roles;
  allNodes = controlPlaneNodeList ++ workerNodeList;

  nodeLabels = lib.listToAttrs (
    map (node: {
      name = node.machineName;
      value = node.kubernetes.nodeLabels or { };
    }) allNodes
  );

in
{
  options = {
    services.kubernetes.nodeLabels = lib.mkOption {
      type = with lib.types; attrsOf (attrsOf str);
      default = { };
      description = ''
        Additional labels to add to each node in the cluster. The labels defined here
        will be added to the default kubelet labels by the kubernetes addon manager.
      '';
      example = {
        machine1 = {
          "environment" = "production";
          "zone" = "us-west-1a";
        };
        machine2 = {
          "environment" = "test";
          "zone" = "us-west-1a";
        };
      };
    };
  };

  config.services.kubernetes = {

    inherit nodeLabels;

    addonManager = {
      addons = {
        node-manifest = {
          apiVersion = "v1";
          kind = "NodeList";
          items =
            # build a Node object for each node in the cluster (control-plane + workers)
            lib.map (
              node:
              let
                nodeIsControlPlane = builtins.any (n: n.machineName == node.machineName) controlPlaneNodeList;
                nodeIsEtcd = builtins.any (n: n.machineName == node.machineName) etcdNodeList;
                nodeIsWorker = builtins.any (n: n.machineName == node.machineName) workerNodeList;
              in
              {
                apiVersion = "v1";
                kind = "Node";
                metadata = {
                  name = node.fqdn;
                  labels =
                    # User defined node labels
                    config.services.kubernetes.nodeLabels."${node.machineName}"
                    //
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

                      # Document the configured components
                      "components.cluster.nixos.org/etcd-member" = if nodeIsEtcd then "true" else "false";
                      "components.cluster.nixos.org/scheduler" = if nodeIsControlPlane then "true" else "false";
                      "components.cluster.nixos.org/controller-manager" = if nodeIsControlPlane then "true" else "false";
                      "components.cluster.nixos.org/api-server" = if nodeIsControlPlane then "true" else "false";
                      "components.cluster.nixos.org/haproxy" = "true";

                      # Give the kubernetes addon manager the ability to manage this resource
                      "addonmanager.kubernetes.io/mode" = "Reconcile";
                    };
                };
              }
            ) allNodes;
        };
      };
    };
  };
}
