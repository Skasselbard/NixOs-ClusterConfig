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
    import ./api-server-mapper.nix {
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
      caFile = certificates.etcd.caCertFile.targetPath;
      certFile = certificates.apiServer.etcdClientCertFile.targetPath;
      keyFile = certificates.apiServer.etcdClientKeyFile.targetPath;
    };

    clientCaFile = certificates.caCertFile.targetPath;

    kubeletClientCertFile = certificates.apiServer.kubeletClientCertFile.targetPath;
    kubeletClientKeyFile = certificates.apiServer.kubeletClientKeyFile.targetPath;

    serviceAccountKeyFile = certificates.saPubFile.targetPath;
    serviceAccountSigningKeyFile = certificates.saKeyFile.targetPath;

    tlsCertFile = certificates.apiServer.certFile.targetPath;
    tlsKeyFile = certificates.apiServer.keyFile.targetPath;

  };
}
