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
{
  clusterInfo,
  selectors,
  roles,
  this,
}:

{ config, lib, ... }:

with lib;

let
  # static values
  defaultSourcePrefix = "/var/lib/kubernetes/pki/";
  defaultTargetPrefix = "/etc/kubernetes/pki/";

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

  certs = config.services.kubernetes.cluster.certificates;

  # Helper to build the options each cert uses
  certOptions = name: default: {
    sourcePath = mkOption {
      type = types.str;
      default = defaultSourcePrefix + default;
      description = "Path to the ${name} file from where the file will be linked. Defaults to ${defaultSourcePrefix + default}";
    };
    targetPath = mkOption {
      type = types.str;
      default = defaultTargetPrefix + default;
      description = "Path to the ${name} file. Defaults to ${defaultTargetPrefix + default}";
    };
  };

  # build a tmpfile.rules link entry
  lnk =
    target: source: user: group: permissions:
    "L+ ${target} ${permissions} ${user} ${group} - ${source}";

in
{
  options.services.kubernetes.cluster.certificates = {
    generation = {

      organization = mkOption {
        type = types.str;
        description = "";
      };

      organizationUnit = mkOption {
        type = types.str;
        description = "";
      };

      country = mkOption {
        type = types.str;
        description = "";
      };

      province = mkOption {
        type = types.str;
        description = "";
      };

      locality = mkOption {
        type = types.str;
        description = "";
      };

      # domain = mkOption {
      #   type = types.str;
      #   default = clusterInfo.fqdn;
      #   description = "";
      # };

      # issuer = mkOption {
      #   type = types.str;
      #   default =
      #     config.services.kubernetes.cluster.certificates.generation.organizationUnit
      #     + "/"
      #     + config.services.kubernetes.cluster.certificates.generation.organization;
      #   description = "";
      # };

    };

    caCertFile = certOptions "caCertFile" "ca.crt";
    caKeyFile = certOptions "caKeyFile" "ca.key";

    etcd = {
      caCertFile = certOptions "etcdCaCertFile" "etcd/ca.crt";
      caKeyFile = certOptions "etcdCaKeyFile" "etcd/ca.key";

      serverCertFile = certOptions "etcdServerCertFile" "etcd/server.crt";
      serverKeyFile = certOptions "etcdServerKeyFile" "etcd/server.key";

      peerCertFile = certOptions "etcdPeerCertFile" "etcd/peer.crt";
      peerKeyFile = certOptions "etcdPeerKeyFile" "etcd/peer.key";

      etcdHealthcheckClientCertFile = certOptions "etcdHealthcheckClientCertFile" "etcd/healthcheck-client.crt";
      etcdHealthcheckClientKeyFile = certOptions "etcdHealthcheckClientKeyFile" "etcd/healthcheck-client.key";
    };

    apiServer = {
      certFile = certOptions "apiserverCertFile" "apiserver.crt";
      keyFile = certOptions "apiserverKeyFile" "apiserver.key";

      kubeletClientCertFile = certOptions "apiserverKubeletClientCertFile" "apiserver-kubelet-client.crt";
      kubeletClientKeyFile = certOptions "apiserverKubeletClientKeyFile" "apiserver-kubelet-client.key";

      etcdClientCertFile = certOptions "apiserverEtcdClientCertFile" "apiserver-etcd-client.crt";
      etcdClientKeyFile = certOptions "apiserverEtcdClientKeyFile" "apiserver-etcd-client.key";
    };

    addonManagerCertFile = certOptions "addonManagerCertFile" "addon-manager.crt";
    addonManagerKeyFile = certOptions "addonManagerKeyFile" "addon-manager.key";

    controllerManagerCertFile = certOptions "controllerManagerCertFile" "controller-manager.crt";
    controllerManagerKeyFile = certOptions "controllerManagerKeyFile" "controller-manager.key";

    kubeletCertFile = certOptions "kubeletCertFile" "kubelet.crt";
    kubeletKeyFile = certOptions "kubeletKeyFile" "kubelet.key";

    schedulerCertFile = certOptions "schedulerCertFile" "scheduler.crt";
    schedulerKeyFile = certOptions "schedulerKeyFile" "scheduler.key";

    saKeyFile = certOptions "saKeyFile" "sa.key";
    saPubFile = certOptions "saPubFile" "sa.pub";

  };

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
          (lnk certs.etcd.etcdHealthcheckClientCertFile.targetPath
            certs.etcd.etcdHealthcheckClientCertFile.sourcePath
            user.etcd
            group.etcd
            permissions.publicRead
          )
          (lnk certs.etcd.etcdHealthcheckClientKeyFile.targetPath
            certs.etcd.etcdHealthcheckClientKeyFile.sourcePath
            user.etcd
            group.etcd
            permissions.privateUser
          )
        ]
      else
        [ ]
    );
}
