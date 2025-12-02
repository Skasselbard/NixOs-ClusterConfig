{
  config,
  lib,
  kubeLib,
  ...
}:
let

  cluster = config.clusterConfig.clusters.this;
  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;
  this = config.clusterConfig.clusters.this.machines.this;
  certificates = cluster.services.kubernetes.certificates;

  apiServerPort = 6443;

  controlPlaneNodeList = kubeLib.getControlPlaneList roles;
  enable = (builtins.any (node: node.name == this.name) controlPlaneNodeList);

in
lib.mkIf enable {

  services.kubernetes.controllerManager = {
    enable = true;
    securePort = 10257;
    kubeconfig = {
      caFile = certificates.caCertFile.targetPath;
      certFile = certificates.controllerManagerCertFile.targetPath;
      keyFile = certificates.controllerManagerKeyFile.targetPath;
      server = kubeLib.mkUrl apiServerPort "kubernetes.${cluster.fqdn}";
    };

    rootCaFile = certificates.caCertFile.targetPath;
    serviceAccountKeyFile = certificates.saKeyFile.targetPath;
  };

}
