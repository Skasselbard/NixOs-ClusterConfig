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

  # flake inputs from the cluster module
  nixhelm,
  nix-kube-generators,
  ...
}:

let
  #imports
  str = lib.types.str;
  mkOption = lib.mkOption;

in

{

  ##########################################################
  # Additional options for cluster configuration.
  # Other options are defined in the nixos service module for kubernetes.

  options.services.kubernetes.cluster = {

    clusterName = mkOption {
      type = str;
      default = "kubernetes." + clusterInfo.fqdn;
    };

    virtualIps = mkOption {
      description = ''
        A list of IP addresses the cluster should be available on.

        You can add a netmask suffix to the ip.
      '';
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "10.0.0.1"
        "192.168.200.20/24"
      ];
    };

  };

  ###############################################
  imports = [
    (import ./addons {
      inherit
        clusterInfo
        selectors
        roles
        this
        ;
    })
    (import ./certificates.nix {
      inherit
        clusterInfo
        selectors
        roles
        this
        ;
    })
    (import ./control-plane/etcd.nix {
      inherit
        clusterInfo
        selectors
        roles
        this
        ;
    })
    (import ./control-plane/api-server.nix {
      inherit
        clusterInfo
        selectors
        roles
        this
        ;
    })
    (import ./control-plane/controller-manager.nix {
      inherit
        clusterInfo
        selectors
        roles
        this
        ;
    })
    (import ./control-plane/scheduler.nix {
      inherit
        clusterInfo
        selectors
        roles
        this
        ;
    })
    (import ./control-plane/haProxy.nix {
      inherit
        clusterInfo
        selectors
        roles
        this
        ;
    })
    (import ./control-plane/keepalived.nix {
      inherit
        clusterInfo
        selectors
        roles
        this
        ;
    })
    (import ./kubelet/kubelet.nix {
      inherit
        clusterInfo
        selectors
        roles
        this
        ;
    })
  ];

  config =

    let
      cfg = config.services.kubernetes;
    in

    {
      _module.args = {
        kubeLib = import ./kubelib.nix {
          inherit
            pkgs
            lib
            nix-kube-generators
            nixhelm
            ;
        };
      };
      environment.systemPackages = with pkgs; [
        kubernetes
        certstrap
        cri-tools
        openssl
      ];

      services.kubernetes = {
        # masterAddress = "master.example.com";
        # clusterCidr = "10.200.0.0/16";
        pki.enable = false; # Don't use easyCerts; Certs are not easy!
      };
    };

}
