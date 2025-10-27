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
  controlPlaneNodeList = kubeLib.getControlPlaneList roles;
  workerNodeList = kubeLib.getWorkerList roles;

  #############################
  # Helper Functions
  mkUrls = kubeLib.mkUrls;

  # If the node is a controlplane node but not a worker node, mark it as unschedulable
  unschedulable =
    (builtins.any (node: node.machineName == this.machineName) controlPlaneNodeList)
    && !(builtins.any (node: node.machineName == this.machineName) workerNodeList);

in
{

  config = {
    swapDevices = lib.mkForce [ ]; # disable swap

    services.kubernetes.kubelet = {
      enable = true;
      unschedulable = unschedulable;
      hostname = this.fqdn;
      # clusterDomain
      kubeconfig = {
        caFile = cfg.certificates.caCertFile.targetPath;
        certFile = cfg.certificates.kubeletCertFile.targetPath;
        keyFile = cfg.certificates.kubeletKeyFile.targetPath;
        server = builtins.head (mkUrls apiServerPort (map (node: node.fqdn) controlPlaneNodeList));
      };
    };

    #   clusterDNS
    # # can
    # registerWithTaints
    # # may
    # systemReserved { cpu: "200m", memory: "256Mi" } Reserve resources for system processes
    # logging.format "json"
  };
}
