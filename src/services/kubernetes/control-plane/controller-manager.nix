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

  services.kubernetes.controllerManager = {
    enable = true;
    kubeconfig = {
      caFile = cfg.certificates.caCertFile.targetPath;
      certFile = cfg.certificates.controllerManagerCertFile.targetPath;
      keyFile = cfg.certificates.controllerManagerKeyFile.targetPath;
      server = mkUrl apiServerPort (builtins.head (kubeLib.getControlPlaneFqdns roles));
    };

    serviceAccountKeyFile = cfg.certificates.saKeyFile.targetPath;
  };

}
