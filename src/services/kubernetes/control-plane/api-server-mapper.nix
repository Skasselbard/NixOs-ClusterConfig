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
  kubeLib,
  ...
}:

let
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
