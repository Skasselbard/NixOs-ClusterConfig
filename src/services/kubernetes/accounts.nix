{ lib, ... }:

with lib;

let
  confOption = name: default: {
    options.${name} = mkOption {
      type = types.str;
      default = default;
      description = "Path to the ${name} file. Defaults to ${default}";
    };
  };
in
{
  options.kubernetes.cluster.accounts = {
    adminConf = confOption "adminConfFile" "/etc/kubernetes/admin.conf";
    controllerManager = confOption "controllerManagerConf" "/etc/kubernetes/controller-manager.conf";
    scheduler = confOption "schedulerConf" "/etc/kubernetes/scheduler.conf";
    kubelet = confOption "kubeletConf" "/etc/kubernetes/kubelet.conf";
  };
}
