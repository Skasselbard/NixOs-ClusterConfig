{
  control-plane-config,
  controlPlaneMachines,
  etcdMachines,
  pkgs,
  lib,
  ...
}:
let
  # imports
  flatten = lib.lists.flatten;
  remove = lib.lists.remove;

  # get a list of ips excluding dhcp configurations
  parseRealIps =
    ips:
    let
      ipList = flatten (lib.attrsets.mapAttrsToList (name: value: value) ips);
    in
    remove "dhcp" ipList;

  # get the config from the picked machines
  cfg = control-plane-config.services.kubernetes;

  # Certdata to configure: https://kubernetes.io/docs/setup/best-practices/certificates/
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
    }
    // builtins.listToAttrs (
      builtins.concatMap (machine: [
        {
          name = "server-${machine.annotations.machineName}";
          value = {
            name = "etcd-server-${machine.annotations.machineName}";
            domains = [
              "localhost"
              machine.annotations.fqdn
            ];
            ips = [ "127.0.0.1" ] ++ parseRealIps machine.annotations.ips;
            passPhrase = "";
          };
        }
        {
          name = "peer-${machine.annotations.machineName}";
          value = {
            name = "etcd-peer-${machine.annotations.machineName}";
            domains = [
              "localhost"
              machine.annotations.fqdn
            ];
            ips = [ "127.0.0.1" ] ++ parseRealIps machine.annotations.ips;
            passPhrase = "";
          };
        }
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
        admin = {
          name = "admin";
          kubernetesGroup = "system:masters";
          passPhrase = "";
        };
      }
      // builtins.listToAttrs (
        builtins.concatMap (machine: [
          {
            name = "apiserver-${machine.annotations.machineName}";
            value = {
              name = "apiserver-${machine.annotations.machineName}";
              domains = [
                "localhost"
                machine.annotations.fqdn
              ];
              ips = [ "127.0.0.1" ] ++ parseRealIps machine.annotations.ips;
              passPhrase = "";
            };
          }
          {
            name = "kubelet-client-${machine.annotations.machineName}";
            value = {
              name = "kubelet-client-${machine.annotations.machineName}";
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
