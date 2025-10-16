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
  cfg = config.services.kubernetes.cluster;
  apiServerPort = 6443;
  controlPlaneNodeList = roles.controlPlane;

  #############################
  # Helper Functions

  # Create URL from hostname and port
  mkUrl = port: address: "https://${address}:${toString port}";
  mkUrls = port: addresses: map (address: mkUrl port address) addresses;

in
{

  services.kubernetes.controllerManager = {
    enable = true;
    kubeconfig = {
      certFile = cfg.certificates.controllerManagerCertFile.targetPath;
      keyFile = cfg.certificates.controllerManagerKeyFile.targetPath;
      server = builtins.head (mkUrls apiServerPort (map (node: node.fqdn) controlPlaneNodeList));
    };

    serviceAccountKeyFile = cfg.certificates.saPubFile.targetPath;
  };

}
