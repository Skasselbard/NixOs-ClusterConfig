{
  config,
  pkgs,
  kubeLib,
  ...
}:

let

  cluster = config.clusterConfig.clusters.this;
  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;
  this = config.clusterConfig.clusters.this.machines.this;
  certificates = cluster.services.kubernetes.certificates;

  apiServerPort = 6443;
  controlPlaneNodeList = kubeLib.getControlPlaneList roles;

  addonManager.kubeconfig = {
    caFile = certificates.caCertFile.targetPath;
    certFile = certificates.addonManagerCertFile.targetPath;
    keyFile = certificates.addonManagerKeyFile.targetPath;
    server = builtins.head (kubeLib.mkUrls apiServerPort (map (node: node.fqdn) controlPlaneNodeList));
  };

  kubeconfig = config.services.kubernetes.lib.mkKubeConfig "kubelet" addonManager.kubeconfig;
in
{
  imports = [
    ./cni
    ./cni/cilium.nix
    ./node-labeling.nix
  ];
  config = {

    systemd.services.kube-addon-manager.environment = {
      KUBECTL_BIN = "${pkgs.kubectl}/bin/kubectl";
      KUBECTL_OPTS = "--kubeconfig ${kubeconfig}";
      SYSTEM_NAMESPACE = "kube-system";
      ADDON_MANAGER_LEADER_ELECTION = "true";
      ADDON_CHECK_INTERVAL_SEC = "60";
    };

    services.kubernetes.addonManager = {
      # enable addonManager on control plane nodes
      enable = builtins.any (node: node.name == this.name) controlPlaneNodeList;
    };

  };
}
