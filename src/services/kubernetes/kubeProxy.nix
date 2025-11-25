{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:

let
  cfg = config.services.kubernetes.cluster;
  apiServerPort = 6443;
  workerNodeList = kubeLib.getWorkerList roles;

  cluster = config.clusterConfig.clusters.this;
  selectors = config.clusterConfig.clusters.this.services.kubernetes.selectors;
  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;
  this = config.clusterConfig.clusters.this.machines.this;

  #############################
  # Helper Functions
  mkUrl = kubeLib.mkUrl;

  isWorkerNode = builtins.any (node: node.machineName == this.name) workerNodeList;
  runsCilium = config.services.kubernetes.addons ? cilium;
in
{
  services.kubernetes.proxy = {
    # enable if worker role is defined for this node
    enable = isWorkerNode && !runsCilium;
    kubeconfig = {
      caFile = cfg.certificates.caCertFile.targetPath;
      certFile = cfg.certificates.proxyCertFile.targetPath;
      keyFile = cfg.certificates.proxyKeyFile.targetPath;
      server = mkUrl apiServerPort "kubernetes.${cluster.fqdn}";
    };
  };
}
