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

  };

  ###############################################
  imports = [
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
    (import ./haProxy.nix {
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
      kubeLib = import ./kubelib.nix { inherit lib; };

      cfg = config.services.kubernetes;

    in

    {
      # TODO: Validation
      # check if controlPlane role is empty

      environment.systemPackages = with pkgs; [
        kubernetes
        certstrap
        openssl
      ];

      services.kubernetes = {
        # masterAddress = "master.example.com";
        # clusterCidr = "10.200.0.0/16";
        pki.enable = false; # Don't use easyCerts; Certs are not easy!
      };
    };

}
