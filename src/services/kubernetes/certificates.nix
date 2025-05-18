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

{ lib, ... }:

with lib;

let
  certOption = name: default: {
    options.${name} = mkOption {
      type = types.str;
      default = default;
      description = "Path to the ${name} file. Defaults to ${default}";
    };
  };
in
{
  options.services.kubernetes.cluster.certificates = {
    caCertFile = certOption "caCertFile" "/etc/kubernetes/pki/ca.crt";
    caKeyFile = certOption "caKeyFile" "/etc/kubernetes/pki/ca.key";

    etcd = {
      caCertFile = certOption "etcdCaCertFile" "/etc/kubernetes/pki/etcd/ca.crt";
      caKeyFile = certOption "etcdCaKeyFile" "/etc/kubernetes/pki/etcd/ca.key";

      serverCertFile = certOption "etcdServerCertFile" "/etc/kubernetes/pki/etcd/server.crt";
      serverKeyFile = certOption "etcdServerKeyFile" "/etc/kubernetes/pki/etcd/server.key";

      peerCertFile = certOption "etcdPeerCertFile" "/etc/kubernetes/pki/etcd/peer.crt";
      peerKeyFile = certOption "etcdPeerKeyFile" "/etc/kubernetes/pki/etcd/peer.key";

      etcdHealthcheckClientCertFile = certOption "etcdHealthcheckClientCertFile" "/etc/kubernetes/pki/etcd/healthcheck-client.crt";
      etcdHealthcheckClientKeyFile = certOption "etcdHealthcheckClientKeyFile" "/etc/kubernetes/pki/etcd/healthcheck-client.key";
    };

    apiServer = {
      certFile = certOption "apiserverCertFile" "/etc/kubernetes/pki/apiserver.crt";
      keyFile = certOption "apiserverKeyFile" "/etc/kubernetes/pki/apiserver.key";

      kubeletClientCertFile = certOption "apiserverKubeletClientCertFile" "/etc/kubernetes/pki/apiserver-kubelet-client.crt";
      kubeletClientKeyFile = certOption "apiserverKubeletClientKeyFile" "/etc/kubernetes/pki/apiserver-kubelet-client.key";

      etcdClientCertFile = certOption "apiserverEtcdClientCertFile" "/etc/kubernetes/pki/apiserver-etcd-client.crt";
      etcdClientKeyFile = certOption "apiserverEtcdClientKeyFile" "/etc/kubernetes/pki/apiserver-etcd-client.key";
    };

    # front-proxy certificates are required only if you run kube-proxy to support an extension API server.
    # ###
    # frontProxyCaCertFile = certOption "frontProxyCaCertFile" "/etc/kubernetes/pki/front-proxy-ca.crt";
    # frontProxyCaKeyFile = certOption "frontProxyCaKeyFile" "/etc/kubernetes/pki/front-proxy-ca.key";

    # frontProxyClientCertFile = certOption "frontProxyClientCertFile" "/etc/kubernetes/pki/front-proxy-client.crt";
    # frontProxyClientKeyFile = certOption "frontProxyClientKeyFile" "/etc/kubernetes/pki/front-proxy-client.key";

    saKeyFile = certOption "saKeyFile" "/etc/kubernetes/pki/sa.key";
    saPubFile = certOption "saPubFile" "/etc/kubernetes/pki/sa.pub";

  };
}
