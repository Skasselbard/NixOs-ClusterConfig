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

  cfg = config.services.kubernetes.cluster;
  apiServerPort = 6443;

  #############################
  # Helper Functions

  # Create URL from hostname and port
  mkUrl = kubeLib.mkUrl;

in
{

  services.kubernetes.scheduler = {
    enable = true;
    kubeconfig = {
      caFile = cfg.certificates.caCertFile.targetPath;
      certFile = cfg.certificates.schedulerCertFile.targetPath;
      keyFile = cfg.certificates.schedulerKeyFile.targetPath;
      # TODO: use kubernetes fqdn as server
      server = mkUrl apiServerPort "kubernetes.${clusterInfo.fqdn}";
    };

  };

}
