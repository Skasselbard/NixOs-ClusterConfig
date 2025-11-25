{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:

let
  cluster = config.clusterConfig.clusters.this;

  ciliumChart =
    (kubeLib.helm.charts {
      namespace = "cni";
      extraHelmOpts = [ "--labels 'addonmanager.kubernetes.io/mode=Reconcile'" ];
      values = {
        k8sServiceHost = "kubernetes.${cluster.fqdn}";
        k8sServicePort = 6443;
        kubeProxyReplacement = true;
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
