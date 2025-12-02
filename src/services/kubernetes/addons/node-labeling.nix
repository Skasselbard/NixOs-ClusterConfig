{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:

let

  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;

  controlPlaneNodeList = kubeLib.getControlPlaneList roles;
  etcdNodeList = kubeLib.getEtcdList roles;
  workerNodeList = kubeLib.getWorkerList roles;
  allNodes = controlPlaneNodeList ++ workerNodeList;

  nodeLabels = lib.listToAttrs (
    map (node: {
      name = node.name;
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
                nodeIsControlPlane = builtins.any (n: n.name == node.name) controlPlaneNodeList;
                nodeIsEtcd = builtins.any (n: n.name == node.name) etcdNodeList;
                nodeIsWorker = builtins.any (n: n.name == node.name) workerNodeList;
                unschedulable = !nodeIsWorker;

                release = node.config.system.nixos.release;
                codeName = node.config.system.nixos.codeName;
                kernelVersion = node.config.boot.kernelPackages.kernel.version;
              in
              {
                apiVersion = "v1";
                kind = "Node";
                spec = {
                  inherit unschedulable;
                  taints =
                    if unschedulable then
                      [
                        {
                          effect = "NoSchedule";
                          key = "unschedulable";
                          value = if unschedulable then "true" else "false";
                        }
                        {
                          effect = "NoSchedule";
                          key = "node.kubernetes.io/unschedulable";
                          value = "";
                        }
                      ]
                    else
                      [ ];
                };
                metadata = {
                  name = node.fqdn;
                  labels =
                    # User defined node labels
                    config.services.kubernetes.nodeLabels."${node.name}"
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
                      "cluster.nixos.org/hostname" = node.name;
                      "cluster.nixos.org/release" = release;
                      "cluster.nixos.org/codename" = codeName;
                      "cluster.nixos.org/kernel" = kernelVersion;

                      # Document the configured components
                      "components.cluster.nixos.org/etcd-member" = if nodeIsEtcd then "true" else "false";
                      "components.cluster.nixos.org/scheduler" = if nodeIsControlPlane then "true" else "false";
                      "components.cluster.nixos.org/controller-manager" = if nodeIsControlPlane then "true" else "false";
                      "components.cluster.nixos.org/api-server" = if nodeIsControlPlane then "true" else "false";
                      # "components.cluster.nixos.org/haproxy" = "true";
                      # "components.cluster.nixos.org/keepalived" = "true";

                      # TODO:
                      # keepalived cluster address
                      # keepalived priority
                      # keepalived interface

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
