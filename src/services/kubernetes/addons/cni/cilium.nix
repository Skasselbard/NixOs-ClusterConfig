{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:

let
  cfg = config.services.kubernetes.cluster;

  ciliumChart =
    (kubeLib.helm.charts {
      namespace = "cni";
      extraHelmOpts = [ "--labels 'addonmanager.kubernetes.io/mode=Reconcile'" ];
      values = {
        k8sServiceHost = cfg.clusterName;
        k8sServicePort = 6443;
        kubeProxyReplacement = true;
        # tls.ca.cert = builtins.readFile cfg.certificates.caCertFile.targetPath;
        # hostFirewall = {
        #   enabled = true;
        # };
      };
    }).cilium.cilium;

  ciliumConfig = map (res: {
    name = "cilium-${res.kind}-${res.metadata.name}";
    value = lib.recursiveUpdate res {
      # add the addonmanager label to each resource
      metadata.labels."addonmanager.kubernetes.io/mode" = "Reconcile";
    };
  }) ciliumChart;
in
lib.mkIf (config.services.kubernetes.cluster.cniPlugin == "cilium") {

  environment.systemPackages = [
    pkgs.cilium-cli
  ];

  services.kubernetes.kubelet.cni.packages = [
    pkgs.cilium-cli
  ];

  services.kubernetes.addonManager.addons = builtins.listToAttrs ciliumConfig;

  services.kubernetes.proxy.enable = false;
}
