{
  lib,
  ...
}:
let
  #imports
  enum = lib.types.enum;
  mkOption = lib.mkOption;
in

{

  config = {
    # Allow privileged workloads (required for all CNIs including Cilium)
    services.kubernetes.apiserver.allowPrivileged = true;

    # network plugins need to write to /etc/cni/net.d but the state does not need to be persistent
    fileSystems."/etc/cni/net.d" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0755" ];
    };

    services.kubernetes.addonManager.addons.privileged-kube-system = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata = {
        name = "cni";
        labels = {
          # Give the kubernetes addon manager the ability to manage this resource
          "addonmanager.kubernetes.io/mode" = "Reconcile";
        };
      };
    };
  };
}
