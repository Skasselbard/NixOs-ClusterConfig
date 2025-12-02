{
  config,
  lib,
  kubeLib,
  ...
}:
let
  apiServerPort = 6443;

  cluster = config.clusterConfig.clusters.this;
  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;
  this = config.clusterConfig.clusters.this.machines.this;
  certificates = cluster.services.kubernetes.certificates;

  controlPlaneNodeList = kubeLib.getControlPlaneList roles;
  enable = (builtins.any (node: node.name == this.name) controlPlaneNodeList);

in
lib.mkIf enable {

  services.kubernetes.scheduler = {
    enable = true;
    port = 10259;
    kubeconfig = {
      caFile = certificates.caCertFile.targetPath;
      certFile = certificates.schedulerCertFile.targetPath;
      keyFile = certificates.schedulerKeyFile.targetPath;
      server = kubeLib.mkUrl apiServerPort "kubernetes.${cluster.fqdn}";
    };

  };

}
