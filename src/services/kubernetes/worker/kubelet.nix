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
  apiServerPort = config.services.kubernetes.apiserver.securePort;
  controlPlaneNodeList = roles.controlPlane;

  #############################
  # Helper Functions

  # Create URL from hostname and port
  mkUrl = port: address: "https://${address}:${toString port}";
  mkUrls = port: addresses: map (address: mkUrl port address) addresses;
in
{

  networking.firewall.allowedTCPPorts = [ cfg.services.kubernetes.apiserver.securePort ];

  services.kubernetes.kubelet = {
    enable = true;
    unschedulable = false;
    hostname = this.fqdn;
    kubeconfig = {
      caFile = cfg.certificates.caCertFile.targetPath;
      certFile = cfg.certificates.kubeletCertFile.targetPath;
      keyFile = cfg.certificates.kubeletKeyFile.targetPath;
      # TODO: use kubernetes fqdn as server
      server = builtins.head (mkUrls apiServerPort (map (node: node.fqdn) controlPlaneNodeList));
    };
    # clientCaFile = cfg.certificates.caCertFile.targetPath;
    # tlsCertFile = cfg.certificates.kubeletCertFile.targetPath;
    # tlsKeyFile = cfg.certificates.kubeletKeyFile.targetPath;
  };

}
