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
  kubeLib,
  ...
}:

let

  cfg = config.services.kubernetes.cluster;
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

    (import ./node-labeling.nix
      {
        inherit
          clusterInfo
          selectors
          roles
          this
          ;
      }
      {
        inherit
          config
          lib
          pkgs
          kubeLib
          ;
      }
    )

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
