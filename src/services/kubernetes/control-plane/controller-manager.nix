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
  apiServerPort = config.services.kubernetes.apiserver.securePort;

  #############################
  # Helper Functions

  # Create URL from hostname and port
  mkUrl = kubeLib.mkUrl;

in
{

  services.kubernetes.controllerManager = {
    enable = true;
    kubeconfig = {
      certFile = cfg.certificates.controllerManagerCertFile.targetPath;
      keyFile = cfg.certificates.controllerManagerKeyFile.targetPath;
      # TODO: use kubernetes fqdn as server
      server = mkUrl apiServerPort (builtins.head (kubeLib.getControlPlaneFqdns roles));
    };

    serviceAccountKeyFile = cfg.certificates.saPubFile.targetPath;
  };

}
