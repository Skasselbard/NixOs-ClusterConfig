{
  lib,
  pkgs,

  # flake inputs from the cluster module
  nixhelm,
  nix-kube-generators,
  ...
}:
{

  ###############################################
  imports = [
    ./addons
    ./certificates/machineLinks.nix
    ./control-plane
    ./kubelet/kubelet.nix
  ];

  config = {

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
