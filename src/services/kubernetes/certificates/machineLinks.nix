# Certificate paths best practice: https://kubernetes.io/docs/setup/best-practices/certificates/#certificate-paths
# /etc/kubernetes/pki/etcd/ca.key
# /etc/kubernetes/pki/etcd/ca.crt
# /etc/kubernetes/pki/apiserver-etcd-client.key
# /etc/kubernetes/pki/apiserver-etcd-client.crt
# /etc/kubernetes/pki/ca.key
# /etc/kubernetes/pki/ca.crt
# /etc/kubernetes/pki/apiserver.key
# /etc/kubernetes/pki/apiserver.crt
# /etc/kubernetes/pki/apiserver-kubelet-client.key
# /etc/kubernetes/pki/apiserver-kubelet-client.crt
# /etc/kubernetes/pki/front-proxy-ca.key
# /etc/kubernetes/pki/front-proxy-ca.crt
# /etc/kubernetes/pki/front-proxy-client.key
# /etc/kubernetes/pki/front-proxy-client.crt
# /etc/kubernetes/pki/etcd/server.key
# /etc/kubernetes/pki/etcd/server.crt
# /etc/kubernetes/pki/etcd/peer.key
# /etc/kubernetes/pki/etcd/peer.crt
# /etc/kubernetes/pki/etcd/healthcheck-client.key
# /etc/kubernetes/pki/etcd/healthcheck-client.crt
# /etc/kubernetes/pki/sa.key
# /etc/kubernetes/pki/sa.pub
{ config, lib, ... }:

with lib;

let

  user = {
    root = config.users.users.root.name;
    etcd = config.users.users.etcd.name;
    kubernetes = config.users.users.kubernetes.name;
  };

  group = {
    root = config.users.groups.root.name;
    etcd = config.users.groups.etcd.name;
    kubernetes = config.users.groups.kubernetes.name;
  };

  permissions = {
    privateUser = "0600";
    publicRead = "0644";
  };

  targets = config.clusterConfig.clusters.this.services.kubernetes.certificates;
  sources = config.clusterConfig.clusters.this.machines.this.kubernetes.certificates;
  certs = attrsets.recursiveUpdate targets sources;

  # build a tmpfile.rules link entry
  lnk =
    target: source: user: group: permissions:
    "L+ ${target} ${permissions} ${user} ${group} - ${source}";

in
{

  config.systemd.tmpfiles.rules =
    (
      # if kubernetes user is undefined, no kubernetes config was made
      if hasAttr "kubernetes" config.users.users then
        [
          # Root CA
          (lnk certs.caCertFile.targetPath certs.caCertFile.sourcePath user.kubernetes group.kubernetes
            permissions.publicRead
          )
          (lnk certs.caKeyFile.targetPath certs.caKeyFile.sourcePath user.kubernetes group.kubernetes
            permissions.privateUser
          )

          # API server
          (lnk certs.apiServer.certFile.targetPath certs.apiServer.certFile.sourcePath user.kubernetes
            group.kubernetes
            permissions.publicRead
          )
          (lnk certs.apiServer.keyFile.targetPath certs.apiServer.keyFile.sourcePath user.kubernetes
            group.kubernetes
            permissions.privateUser
          )
          (lnk certs.apiServer.kubeletClientCertFile.targetPath
            certs.apiServer.kubeletClientCertFile.sourcePath
            user.kubernetes
            group.kubernetes
            permissions.publicRead
          )
          (lnk certs.apiServer.kubeletClientKeyFile.targetPath certs.apiServer.kubeletClientKeyFile.sourcePath
            user.kubernetes
            group.kubernetes
            permissions.privateUser
          )
          (lnk certs.apiServer.etcdClientCertFile.targetPath certs.apiServer.etcdClientCertFile.sourcePath
            user.kubernetes
            group.kubernetes
            permissions.publicRead
          )
          (lnk certs.apiServer.etcdClientKeyFile.targetPath certs.apiServer.etcdClientKeyFile.sourcePath
            user.kubernetes
            group.kubernetes
            permissions.privateUser
          )

          # Other Controll-Plane roles
          (lnk certs.addonManagerCertFile.targetPath certs.addonManagerCertFile.sourcePath user.kubernetes
            group.kubernetes
            permissions.publicRead
          )
          (lnk certs.addonManagerKeyFile.targetPath certs.addonManagerKeyFile.sourcePath user.kubernetes
            group.kubernetes
            permissions.privateUser
          )
          (lnk certs.controllerManagerCertFile.targetPath certs.controllerManagerCertFile.sourcePath
            user.kubernetes
            group.kubernetes
            permissions.publicRead
          )
          (lnk certs.controllerManagerKeyFile.targetPath certs.controllerManagerKeyFile.sourcePath
            user.kubernetes
            group.kubernetes
            permissions.privateUser
          )
          (lnk certs.schedulerCertFile.targetPath certs.schedulerCertFile.sourcePath user.kubernetes
            group.kubernetes
            permissions.publicRead
          )
          (lnk certs.schedulerKeyFile.targetPath certs.schedulerKeyFile.sourcePath user.kubernetes
            group.kubernetes
            permissions.privateUser
          )

          # Worker roles
          (lnk certs.kubeletCertFile.targetPath certs.kubeletCertFile.sourcePath user.kubernetes
            group.kubernetes
            permissions.publicRead
          )
          (lnk certs.kubeletKeyFile.targetPath certs.kubeletKeyFile.sourcePath user.kubernetes
            group.kubernetes
            permissions.privateUser
          )
          (lnk certs.proxyCertFile.targetPath certs.proxyCertFile.sourcePath user.kubernetes group.kubernetes
            permissions.publicRead
          )
          (lnk certs.proxyKeyFile.targetPath certs.proxyKeyFile.sourcePath user.kubernetes group.kubernetes
            permissions.privateUser
          )

          # Service account keys
          (lnk certs.saKeyFile.targetPath certs.saKeyFile.sourcePath user.kubernetes group.kubernetes
            permissions.privateUser
          )
          (lnk certs.saPubFile.targetPath certs.saPubFile.sourcePath user.kubernetes group.kubernetes
            permissions.publicRead
          )
        ]
      else
        [ ]
    )
    ++ (
      # if etcd user is undefined, no etcd config was made
      if hasAttr "etcd" config.users.users then
        [
          # etcd
          (lnk certs.etcd.caCertFile.targetPath certs.etcd.caCertFile.sourcePath user.etcd group.etcd
            permissions.publicRead
          )
          (lnk certs.etcd.caKeyFile.targetPath certs.etcd.caKeyFile.sourcePath user.etcd group.etcd
            permissions.privateUser
          )
          (lnk certs.etcd.serverCertFile.targetPath certs.etcd.serverCertFile.sourcePath user.etcd group.etcd
            permissions.privateUser
          )
          (lnk certs.etcd.serverKeyFile.targetPath certs.etcd.serverKeyFile.sourcePath user.etcd group.etcd
            permissions.privateUser
          )
          (lnk certs.etcd.peerCertFile.targetPath certs.etcd.peerCertFile.sourcePath user.etcd group.etcd
            permissions.publicRead
          )
          (lnk certs.etcd.peerKeyFile.targetPath certs.etcd.peerKeyFile.sourcePath user.etcd group.etcd
            permissions.privateUser
          )
          (lnk certs.etcd.healthcheckClientCertFile.targetPath
            certs.etcd.healthcheckClientCertFile.sourcePath
            user.etcd
            group.etcd
            permissions.publicRead
          )
          (lnk certs.etcd.healthcheckClientKeyFile.targetPath
            certs.etcd.healthcheckClientKeyFile.sourcePath
            user.etcd
            group.etcd
            permissions.privateUser
          )
        ]
      else
        [ ]
    );
}
