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

  cluster = config.clusterConfig.clusters.this;
  selectors = config.clusterConfig.clusters.this.services.kubernetes.selectors;
  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;
  this = config.clusterConfig.clusters.this.machines.this;

  #############################
  # Helper Functions
  mkUrl = kubeLib.mkUrl;

  # If the node is a controlplane node but not a worker node, mark it as unschedulable
  unschedulable =
    (builtins.any (node: node.name == this.name) controlPlaneNodeList)
    && !(builtins.any (node: node.name == this.name) workerNodeList);

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
        server = mkUrl apiServerPort "kubernetes.${cluster.fqdn}";
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
