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

  addonManager.kubeconfig = {
    caFile = cfg.certificates.caCertFile.targetPath;
    certFile = cfg.certificates.addonManagerCertFile.targetPath;
    keyFile = cfg.certificates.addonManagerKeyFile.targetPath;
    server = builtins.head (mkUrls apiServerPort (map (node: node.fqdn) controlPlaneNodeList));
  };

  kubeconfig = config.services.kubernetes.lib.mkKubeConfig "kubelet" addonManager.kubeconfig;
  node-manifest = (
    import ./node-manifest.nix
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
          ;
      }
  );
in
{

  config = {
    swapDevices = lib.mkForce [ ]; # disable swap

    systemd.services.kube-addon-manager.environment = {
      KUBECTL_BIN = "${pkgs.kubectl}/bin/kubectl";
      KUBECTL_OPTS = "--kubeconfig ${kubeconfig}";
      SYSTEM_NAMESPACE = "kube-system";
      ADDON_MANAGER_LEADER_ELECTION = "true";
      ADDON_CHECK_INTERVAL_SEC = "60";
    };

    services.kubernetes.addonManager = {
      enable = true; # TODO only on control plane nodes
      addons = {
        inherit node-manifest;
        "test-namespace" = {
          apiVersion = "v1";
          kind = "Namespace";
          metadata = {
            name = "test-namespace";
            labels = {
              "addonmanager.kubernetes.io/mode" = "Reconcile";
            };
          };
        };
      };
    };

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
