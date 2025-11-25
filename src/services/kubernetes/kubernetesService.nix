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

  clusterInfo = config.clusterConfig.clusters.this;
  selectors = config.clusterConfig.clusters.this.kubernetes.selectors;
  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;
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
    ./addons
    ./certificates.nix
    ./control-plane/etcd.nix
    ./control-plane/api-server.nix
    ./control-plane/controller-manager.nix
    ./control-plane/scheduler.nix
    ./control-plane/haProxy.nix
    ./control-plane/keepalived.nix
    ./kubelet/kubelet.nix
    # ./kubeProxy.nix
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
