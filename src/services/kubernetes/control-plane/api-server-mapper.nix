{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:

let
  clusterInfo = config.cluster.services.kubernetes.clusterInfo;
  selectors = config.cluster.services.kubernetes.selectors;
  roles = config.cluster.services.kubernetes.roles;
  this = config.cluster.services.kubernetes.this;

  etcdPort = 2379;
  etcdList = kubeLib.getEtcdList roles;
  controlPlaneNodeList = kubeLib.getControlPlaneList roles;

  #############################
  # Helper Functions
  mkUrl = kubeLib.mkUrl;

in
{
  enable = (builtins.any (node: node.machineName == this.machineName) controlPlaneNodeList);
  etcd = {
    servers = map (node: mkUrl etcdPort node.fqdn) etcdList;
  };

}
