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
  workerNodeList = kubeLib.getWorkerList roles;

  clusterInfo = config.cluster.services.kubernetes.clusterInfo;
  selectors = config.cluster.services.kubernetes.selectors;
  roles = config.cluster.services.kubernetes.roles;
  this = config.cluster.services.kubernetes.this;

  #############################
  # Helper Functions
  mkUrl = kubeLib.mkUrl;

  # If the node is a controlplane node but not a worker node, mark it as unschedulable
  unschedulable =
    (builtins.any (node: node.machineName == this.machineName) controlPlaneNodeList)
    && !(builtins.any (node: node.machineName == this.machineName) workerNodeList);

in
{

  config = {
    swapDevices = lib.mkForce [ ]; # disable swap

    networking.firewall.allowedTCPPorts = [ config.services.kubernetes.kubelet.port ];

    services.kubernetes.kubelet = {
      enable = true;
      unschedulable = unschedulable;
      hostname = this.fqdn;
      # clusterDomain
      kubeconfig = {
        caFile = cfg.certificates.caCertFile.targetPath;
        certFile = cfg.certificates.kubeletCertFile.targetPath;
        keyFile = cfg.certificates.kubeletKeyFile.targetPath;
        server = mkUrl apiServerPort "kubernetes.${clusterInfo.fqdn}";
      };
      clientCaFile = cfg.certificates.caCertFile.targetPath;
    };

    # clusterDNS
    # # can
    # registerWithTaints
    # # may
    # systemReserved { cpu: "200m", memory: "256Mi" } Reserve resources for system processes
    # logging.format "json"
  };
}
