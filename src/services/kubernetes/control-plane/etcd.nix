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
  cfg = config.services.kubernetes.cluster;
  mappedClusterConfig = (
    import ./etcd-mapper.nix
      {
        inherit
          clusterInfo
          selectors
          roles
          this
          ;
      }
      {
        inherit config lib pkgs;
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

  services.etcd = {
    enable = true;
    openFirewall = true;

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
