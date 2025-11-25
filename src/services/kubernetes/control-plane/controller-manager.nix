{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:
let
  cfg = config.services.kubernetes.cluster;

  cluster = config.clusterConfig.clusters.this;
  selectors = config.clusterConfig.clusters.this.services.kubernetes.selectors;
  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;
  this = config.clusterConfig.clusters.this.machines.this;

  apiServerPort = 6443;

  controlPlaneNodeList = kubeLib.getControlPlaneList roles;
  enable = (builtins.any (node: node.name == this.name) controlPlaneNodeList);

  #############################
  # Helper Functions

  # Create URL from hostname and port
  mkUrl = kubeLib.mkUrl;

in
lib.mkIf enable {

  services.kubernetes.controllerManager = {
    enable = true;
    securePort = 10257;
    kubeconfig = {
      caFile = cfg.certificates.caCertFile.targetPath;
      certFile = cfg.certificates.controllerManagerCertFile.targetPath;
      keyFile = cfg.certificates.controllerManagerKeyFile.targetPath;
      server = mkUrl apiServerPort "kubernetes.${cluster.fqdn}";
    };

    rootCaFile = cfg.certificates.caCertFile.targetPath;
    serviceAccountKeyFile = cfg.certificates.saKeyFile.targetPath;
  };

}
