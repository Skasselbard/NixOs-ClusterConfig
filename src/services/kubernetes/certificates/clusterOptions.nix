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
let
  mkOption = lib.mkOption;
  str = lib.types.str;

  # static values
  defaultSourcePrefix = "/var/lib/kubernetes/pki/";
  defaultTargetPrefix = "/etc/kubernetes/pki/";

  # Helper to build the options each cert uses
  certOptions =
    path: default:
    let
      pathArray = lib.splitString "." path;
      name = builtins.head (lib.reverseList pathArray);
    in
    lib.setAttrByPath ([ "machineOptions" ] ++ pathArray ++ [ "sourcePath" ]) (mkOption {
      type = str;
      default = defaultSourcePrefix + default;
      description = "Path to the ${name} file from where the file will be linked. Defaults to ${defaultSourcePrefix + default}";
    })
    // lib.setAttrByPath ([ "serviceOptions" ] ++ pathArray ++ [ "targetPath" ]) (mkOption {
      type = str;
      default = defaultTargetPrefix + default;
      description = "Path to the ${name} file. Defaults to ${defaultTargetPrefix + default}";
    });

in
lib.foldl (optionsAcc: addedOption: lib.attrsets.recursiveUpdate optionsAcc addedOption) { } [

  (certOptions "caCertFile" "ca.crt")
  (certOptions "caKeyFile" "ca.key")

  #  etcd
  (certOptions "etcd.caCertFile" "etcd/ca.crt")
  (certOptions "etcd.caKeyFile" "etcd/ca.key")

  (certOptions "etcd.serverCertFile" "etcd/server.crt")
  (certOptions "etcd.serverKeyFile" "etcd/server.key")

  (certOptions "etcd.peerCertFile" "etcd/peer.crt")
  (certOptions "etcd.peerKeyFile" "etcd/peer.key")

  (certOptions "etcd.healthcheckClientCertFile" "etcd/healthcheck-client.crt")
  (certOptions "etcd.healthcheckClientKeyFile" "etcd/healthcheck-client.key")

  # apiServer
  (certOptions "apiServer.certFile" "apiserver.crt")
  (certOptions "apiServer.keyFile" "apiserver.key")

  (certOptions "apiServer.kubeletClientCertFile" "apiserver-kubelet-client.crt")
  (certOptions "apiServer.kubeletClientKeyFile" "apiserver-kubelet-client.key")

  (certOptions "apiServer.etcdClientCertFile" "apiserver-etcd-client.crt")
  (certOptions "apiServer.etcdClientKeyFile" "apiserver-etcd-client.key")

  # other
  (certOptions "addonManagerCertFile" "addon-manager.crt")
  (certOptions "addonManagerKeyFile" "addon-manager.key")

  (certOptions "controllerManagerCertFile" "controller-manager.crt")
  (certOptions "controllerManagerKeyFile" "controller-manager.key")

  (certOptions "kubeletCertFile" "kubelet.crt")
  (certOptions "kubeletKeyFile" "kubelet.key")

  (certOptions "proxyCertFile" "proxy.crt")
  (certOptions "proxyKeyFile" "proxy.key")

  (certOptions "schedulerCertFile" "scheduler.crt")
  (certOptions "schedulerKeyFile" "scheduler.key")

  (certOptions "saKeyFile" "sa.key")
  (certOptions "saPubFile" "sa.pub")
]
