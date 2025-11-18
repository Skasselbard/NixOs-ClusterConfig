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
  kubeLib,
  ...
}:

let
  cfg = config.services.kubernetes.cluster;
  mappedClusterConfig = (
    import ./api-server-mapper.nix
      {
        inherit
          clusterInfo
          selectors
          roles
          this
          ;
      }
      {
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

  networking.firewall.allowedTCPPorts = [ config.services.kubernetes.apiserver.securePort ];

  services.kubernetes.apiserver = {
    enable = true;
    # serviceClusterIpRange = "10.0.0.0/24"; # <- use this default
    bindAddress = "127.0.0.1"; # haProxy handles external access
    securePort = 6444; # haProxy binds on 6443 and forwards to 6444

    etcd = {
      servers = mappedClusterConfig.etcd.servers;
      caFile = cfg.certificates.etcd.caCertFile.targetPath;
      certFile = cfg.certificates.apiServer.etcdClientCertFile.targetPath;
      keyFile = cfg.certificates.apiServer.etcdClientKeyFile.targetPath;
    };

    clientCaFile = cfg.certificates.caCertFile.targetPath;

    kubeletClientCertFile = cfg.certificates.apiServer.kubeletClientCertFile.targetPath;
    kubeletClientKeyFile = cfg.certificates.apiServer.kubeletClientKeyFile.targetPath;

    serviceAccountKeyFile = cfg.certificates.saPubFile.targetPath;
    serviceAccountSigningKeyFile = cfg.certificates.saKeyFile.targetPath;

    tlsCertFile = cfg.certificates.apiServer.certFile.targetPath;
    tlsKeyFile = cfg.certificates.apiServer.keyFile.targetPath;

  };
}
