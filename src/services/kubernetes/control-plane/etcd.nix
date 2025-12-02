{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:
let
  cluster = config.clusterConfig.clusters.this;
  certificates = cluster.services.kubernetes.certificates;

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

    trustedCaFile = certificates.etcd.caCertFile.targetPath;

    certFile = certificates.etcd.serverCertFile.targetPath;
    keyFile = certificates.etcd.serverKeyFile.targetPath;
  };

  systemd.services.etcd = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };
}
