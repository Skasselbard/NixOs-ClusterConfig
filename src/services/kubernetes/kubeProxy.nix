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

  clusterInfo = config.cluster.services.kubernetes.clusterInfo;
  selectors = config.cluster.services.kubernetes.selectors;
  roles = config.cluster.services.kubernetes.roles;
  this = config.cluster.services.kubernetes.this;

  #############################
  # Helper Functions
  mkUrl = kubeLib.mkUrl;

  isWorkerNode = builtins.any (node: node.machineName == this.machineName) workerNodeList;
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
      server = mkUrl apiServerPort "kubernetes.${clusterInfo.fqdn}";
    };
  };
}
