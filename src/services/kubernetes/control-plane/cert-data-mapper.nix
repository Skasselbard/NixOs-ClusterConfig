{
  control-plane-config,
  controlPlaneMachines,
  etcdMachines,
  pkgs,
  lib,
  ...
}:
let
  # get the config from the picked machines
  cfg = control-plane-config.services.kubernetes;

  certData = {
    common = {
      org = cfg.cluster.certificates.generation.organization;
      orgUnit = cfg.cluster.certificates.generation.organizationUnit;
      country = cfg.cluster.certificates.generation.country;
      province = cfg.cluster.certificates.generation.province;
      locality = cfg.cluster.certificates.generation.locality;
      # domain = cfg.cluster.certificates.generation.domain;
      # issuer = cfg.cluster.certificates.generation.issuer;
    };
    # role = clusterInfo.name + "-certification";
    k8s = {
      ca = {
        name = "k8s-ca";
        passPhrase = "";
      };
      roles = {
        apiserver = {
          name = "kube-apiserver";
          domains = map (machine: machine.annotations.fqdn) controlPlaneMachines;
          ips = [ ]; # We don't add ips and only use host names fro verification
          passPhrase = "";
        };
        kubelet = {
          name = "system:node:worker-0";
          domains = map (machine: machine.annotations.fqdn) controlPlaneMachines;
          ips = [ ]; # We don't add ips and only use host names fro verification
          passPhrase = "";
        };
        controller-manager = {
          name = "system:kube-controller-manager";
          passPhrase = "";
        };
        scheduler = {
          name = "system:kube-scheduler";
          passPhrase = "";
        };
        admin = {
          name = "admin";
          passPhrase = "";
        };
      };
    };
    etcd = {
      ca = {
        name = "etcd-ca";
        passPhrase = "";
      };
      server = {
        name = "etcd-server";
        domains = map (machine: machine.annotations.fqdn) etcdMachines;
        ips = [ ]; # We don't add ips and only use host names fro verification
        passPhrase = "";
      };
      peer = {
        name = "etcd-peer";
        domains = map (machine: machine.annotations.fqdn) etcdMachines;
        ips = [ ]; # We don't add ips and only use host names fro verification
        passPhrase = "";
      };
    };
  };

  certData-json = builtins.toJSON certData;

  certDate-json-file = pkgs.writeText "certData-config.json" certData-json;

in
{
  inherit certData certData-json certDate-json-file;
}
