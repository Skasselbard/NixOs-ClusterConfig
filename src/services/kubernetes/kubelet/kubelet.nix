{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:

let
  apiServerPort = 6443;
  controlPlaneNodeList = kubeLib.getControlPlaneList roles;
  workerNodeList = kubeLib.getWorkerList roles;

  cluster = config.clusterConfig.clusters.this;
  roles = cluster.services.kubernetes.roles;
  this = cluster.machines.this;
  certificates = cluster.services.kubernetes.certificates;

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
        caFile = certificates.caCertFile.targetPath;
        certFile = certificates.kubeletCertFile.targetPath;
        keyFile = certificates.kubeletKeyFile.targetPath;
        server = kubeLib.mkUrl apiServerPort "kubernetes.${cluster.fqdn}";
      };
      clientCaFile = certificates.caCertFile.targetPath;
    };

    # systemReserved { cpu: "200m", memory: "256Mi" } Reserve resources for system processes
    # logging.format "json"
  };
}
