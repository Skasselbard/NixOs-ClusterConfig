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

  etcdPort = 2379;
  etcdList = kubeLib.getEtcdList roles;

  #############################
  # Helper Functions
  mkUrl = kubeLib.mkUrl;

in
{

  etcd = {
    servers = map (node: mkUrl etcdPort node.fqdn) etcdList;
  };

}
