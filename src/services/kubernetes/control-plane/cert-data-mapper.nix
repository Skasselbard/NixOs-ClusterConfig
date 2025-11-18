{
  clusterFqdn,
  control-plane-config,
  controlPlaneMachines,
  workerMachines,
  etcdMachines,
  pkgs,
  kubeLib,
  lib,
  ...
}:
let
  # get the config from the picked machines
  cfg = control-plane-config.services.kubernetes;

  control-plane-ip-list = kubeLib.getControlPlaneIps {
    controlPlane = map (node: node.annotations) controlPlaneMachines;
  };

  control-plane-fqdn-list = kubeLib.getControlPlaneFqdns {
    controlPlane = map (node: node.annotations) controlPlaneMachines;
  };

  etcd-ip-list = kubeLib.getEtcdIps { etcd = map (node: node.annotations) etcdMachines; };

  etcd-fqdn-list = kubeLib.getEtcdFqdns { etcd = map (node: node.annotations) etcdMachines; };

  # CertData to configure: https://kubernetes.io/docs/setup/best-practices/certificates/
  # https://kubernetes.io/docs/reference/setup-tools/kubeadm/implementation-details/#generate-the-necessary-certificates
  common-cert-data = {
    common = {
      org = cfg.cluster.certificates.generation.organization;
      orgUnit = cfg.cluster.certificates.generation.organizationUnit;
      country = cfg.cluster.certificates.generation.country;
      province = cfg.cluster.certificates.generation.province;
      locality = cfg.cluster.certificates.generation.locality;
      # domain = cfg.cluster.certificates.generation.domain;
      # issuer = cfg.cluster.certificates.generation.issuer;
    };
  };

  etcd-cert-data = {
    etcd = {
      ca = {
        name = "etcd-ca";
        passPhrase = "";
      };
      server = {
        name = "etcd-server";
        domains = [ "localhost" ] ++ etcd-fqdn-list;
        ips = [ "127.0.0.1" ] ++ etcd-ip-list;
        passPhrase = "";
      };
      peer = {
        name = "etcd-peer";
        domains = [ "localhost" ] ++ etcd-fqdn-list;
        ips = [ "127.0.0.1" ] ++ etcd-ip-list;
        passPhrase = "";
      };
    }
    // builtins.listToAttrs (
      builtins.concatMap (machine: [
        {
          name = "apiserver-etcd-client-${machine.annotations.machineName}";
          value = {
            name = "apiserver-etcd-client-${machine.annotations.machineName}";
            domains = [ machine.annotations.fqdn ];
            ips = [ ];
            passPhrase = "";
          };
        }
      ]) etcdMachines
    );
  };

  k8s-cert-data = {
    k8s = {
      ca = {
        name = "k8s-ca";
        passPhrase = "";
      };
      roles = {
        super-admin = {
          name = "kubernetes-super-admin";
          kubernetesGroup = "system:masters";
          passPhrase = "";
        };
        admin = {
          name = "kubernetes-admin";
          kubernetesGroup = "kubeadm:cluster-admins";
          passPhrase = "";
        };
        apiserver = lib.debug.traceSeqN 4 clusterFqdn {
          name = "apiserver";
          domains = [
            "localhost"
            "kubernetes"
            "kubernetes.${clusterFqdn}"
          ]
          ++ control-plane-fqdn-list;
          ips = [ "127.0.0.1" ] ++ control-plane-ip-list ++ cfg.cluster.virtualIps;
          passPhrase = "";
        };
      }
      # Unique certs for each  machine
      // builtins.listToAttrs (
        builtins.concatMap (machine: [
          {
            name = "kubelet-server-${machine.annotations.machineName}";
            value = {
              name = "system:node:${machine.annotations.fqdn}"; # Must match kubelet name
              kubernetesGroup = "system:nodes";
              domains = [ machine.annotations.fqdn ];
              ips = [ ];
              passPhrase = "";
            };
          }
          {
            name = "kubelet-client-${machine.annotations.machineName}";
            value = {
              name = "kube-apiserver-kubelet-client-${machine.annotations.machineName}";
              kubernetesGroup = "system:masters";
              domains = [ ];
              ips = [ ];
              passPhrase = "";
            };
          }
          {
            name = "controller-manager-${machine.annotations.machineName}";
            value = {
              name = "system:kube-controller-manager";
              domains = [ ];
              ips = [ ];
              passPhrase = "";
            };
          }
          {
            name = "scheduler-${machine.annotations.machineName}";
            value = {
              name = "system:kube-scheduler";
              domains = [ ];
              ips = [ ];
              passPhrase = "";
            };
          }
        ]) controlPlaneMachines
      );
    };
  };

  certData = common-cert-data // etcd-cert-data // k8s-cert-data;

  certData-json = builtins.toJSON certData;

  certDate-json-file = pkgs.writeText "certData-config.json" certData-json;

in
{
  inherit certData certData-json certDate-json-file;
}
