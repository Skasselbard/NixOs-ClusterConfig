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
  cfg = config.services.kubernetes.cluster;
  apiServerPort = 6443;

  controlPlaneNodeList = kubeLib.getControlPlaneList roles;
  enable = (builtins.any (node: node.machineName == this.machineName) controlPlaneNodeList);

  #############################
  # Helper Functions

  # Create URL from hostname and port
  mkUrl = kubeLib.mkUrl;

in
lib.mkIf enable {

  services.kubernetes.scheduler = {
    enable = true;
    port = 10259;
    kubeconfig = {
      caFile = cfg.certificates.caCertFile.targetPath;
      certFile = cfg.certificates.schedulerCertFile.targetPath;
      keyFile = cfg.certificates.schedulerKeyFile.targetPath;
      # TODO: use kubernetes fqdn as server
      server = mkUrl apiServerPort "kubernetes.${clusterInfo.fqdn}";
    };

  };

}
