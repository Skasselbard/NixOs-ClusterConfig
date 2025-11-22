{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:

let

  cfg = config.services.kubernetes.cluster;

  clusterInfo = config.cluster.services.kubernetes.clusterInfo;
  selectors = config.cluster.services.kubernetes.selectors;
  roles = config.cluster.services.kubernetes.roles;
  this = config.cluster.services.kubernetes.this;

  apiServerPort = 6443;
  controlPlaneNodeList = kubeLib.getControlPlaneList roles;

  #############################
  # Helper Functions
  mkUrls = kubeLib.mkUrls;

  addonManager.kubeconfig = {
    caFile = cfg.certificates.caCertFile.targetPath;
    certFile = cfg.certificates.addonManagerCertFile.targetPath;
    keyFile = cfg.certificates.addonManagerKeyFile.targetPath;
    server = builtins.head (mkUrls apiServerPort (map (node: node.fqdn) controlPlaneNodeList));
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
      enable = builtins.any (node: node.machineName == this.machineName) controlPlaneNodeList;
    };

  };
}
