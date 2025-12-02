{
  config,
  kubeLib,
  ...
}:

let
  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;
  this = config.clusterConfig.clusters.this.machines.this;

  etcdPort = 2379;
  etcdList = kubeLib.getEtcdList roles;
  controlPlaneNodeList = kubeLib.getControlPlaneList roles;

in
{
  enable = (builtins.any (node: node.name == this.name) controlPlaneNodeList);
  etcd.servers = map (node: kubeLib.mkUrl etcdPort node.fqdn) etcdList;

}
