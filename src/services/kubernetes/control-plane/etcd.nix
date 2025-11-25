{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:
let
  cfg = config.services.kubernetes.cluster;

  cluster = config.clusterConfig.clusters.this;
  selectors = config.clusterConfig.clusters.this.services.kubernetes.selectors;
  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;
  this = config.clusterConfig.clusters.this.machines.this;

  mappedClusterConfig = (
    import ./etcd-mapper.nix {
      inherit
        config
        lib
        pkgs
        kubeLib
        ;
    }
  );

in
lib.mkIf mappedClusterConfig.enable {

  users.groups.etcd = { };
  users.users.etcd = {
    isNormalUser = false;
    isSystemUser = true;
    group = "etcd";
  };

  networking.firewall.allowedTCPPorts = mappedClusterConfig.firewallPorts;

  services.etcd = {
    enable = true;

    name = mappedClusterConfig.nodeName;
    initialCluster = mappedClusterConfig.initialCluster;
    advertiseClientUrls = mappedClusterConfig.advertiseClientUrls;
    initialAdvertisePeerUrls = [ mappedClusterConfig.initialAdvertisePeerUrl ];
    listenClientUrls = mappedClusterConfig.listening.clients;
    listenPeerUrls = mappedClusterConfig.listening.peers;

    clientCertAuth = true;
    peerClientCertAuth = true;

    trustedCaFile = cfg.certificates.etcd.caCertFile.targetPath;

    certFile = cfg.certificates.etcd.serverCertFile.targetPath;
    keyFile = cfg.certificates.etcd.serverKeyFile.targetPath;
  };

  systemd.services.etcd = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };
}
