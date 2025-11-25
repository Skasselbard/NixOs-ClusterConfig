{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:

let
  cluster = config.clusterConfig.clusters.this;
  selectors = config.clusterConfig.clusters.this.services.kubernetes.selectors;
  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;
  this = config.clusterConfig.clusters.this.machines.this;

  etcdPort = 2379;
  etcdList = kubeLib.getEtcdList roles;
  controlPlaneNodeList = kubeLib.getControlPlaneList roles;

  #############################
  # Helper Functions
  mkUrl = kubeLib.mkUrl;

in
{
  enable = (builtins.any (node: node.name == this.name) controlPlaneNodeList);
  etcd = {
    servers = map (node: mkUrl etcdPort node.fqdn) etcdList;
  };

}
