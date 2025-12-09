{
  machineConfig,
  lib,
  ...
}:
let
  machineName = machineConfig.clusterConfig.clusters.this.machines.this.name;
  roles = machineConfig.clusterConfig.clusters.this.services.kubernetes.roles;
  selectors = machineConfig.clusterConfig.clusters.this.services.kubernetes.selectors;
  sources = machineConfig.clusterConfig.clusters.this.machines.this.kubernetes.certificates;

  isControlPlaneMember = lib.any (machine: machine.name == machineName) roles.controlPlane;
  isKubernetesMember = lib.any (machine: machine.name == machineName) selectors;
  isEtcdMember =
    if roles.etcd == [ ] then isControlPlaneMember else lib.any (m: m.name == machineName) roles.etcd;

  etcdSecrets = {
    ca-cert = {
      backendPath = "./certificates/etcd/ca/etcd.crt";
      # backendPath = "./certificates/etcd/intermediates/etcd-ca.crt";
      linkPath = sources.etcd.caCertFile.sourcePath;
      permissions = "555";
    };
    # ca-key = {
    #   backendPath = "./certificates/etcd/ca/etcd.key";
    #   # backendPath = "./certificates/etcd/intermediates/etcd-ca.key";
    #   linkPath = sources.etcd.caKeyFile.sourcePath;
    # };
    server-cert = {
      backendPath = "./certificates/etcd/certs/server.crt";
      linkPath = sources.etcd.serverCertFile.sourcePath;
      permissions = "444";
    };
    server-key = {
      backendPath = "./certificates/etcd/certs/server.key";
      linkPath = sources.etcd.serverKeyFile.sourcePath;
    };
    peer-cert = {
      backendPath = "./certificates/etcd/certs/peer.crt";
      linkPath = sources.etcd.peerCertFile.sourcePath;
      permissions = "444";
    };
    peer-key = {
      backendPath = "./certificates/etcd/certs/peer.key";
      linkPath = sources.etcd.peerKeyFile.sourcePath;
    };
  };

  controlPlaneSecrets = {
    apiserver-server-cert = {
      backendPath = "./certificates/kubernetes/certs/apiserver.crt";
      linkPath = sources.apiServer.certFile.sourcePath;
      permissions = "444";
    };
    apiserver-server-key = {
      backendPath = "./certificates/kubernetes/certs/apiserver.key";
      linkPath = sources.apiServer.keyFile.sourcePath;
    };
    "etcd-client-cert-${machineName}" = {
      backendPath = "./certificates/etcd/certs/apiserver-etcd-client-${machineName}.crt";
      linkPath = sources.apiServer.etcdClientCertFile.sourcePath;
      permissions = "444";
    };
    "etcd-client-key-${machineName}" = {
      backendPath = "./certificates/etcd/certs/apiserver-etcd-client-${machineName}.key";
      linkPath = sources.apiServer.etcdClientKeyFile.sourcePath;
    };

    "kubelet-client-cert-${machineName}" = {
      backendPath = "./certificates/kubernetes/certs/apiserver-kubelet-client-${machineName}.crt";
      linkPath = sources.apiServer.kubeletClientCertFile.sourcePath;
      permissions = "444";
    };
    "kubelet-client-key-${machineName}" = {
      backendPath = "./certificates/kubernetes/certs/apiserver-kubelet-client-${machineName}.key";
      linkPath = sources.apiServer.kubeletClientKeyFile.sourcePath;
    };
    "addon-manager-cert-${machineName}" = {
      backendPath = "./certificates/kubernetes/certs/admin.crt";
      linkPath = sources.addonManagerCertFile.sourcePath;
      permissions = "444";
    };
    "addon-manager-key-${machineName}" = {
      backendPath = "./certificates/kubernetes/certs/admin.key";
      linkPath = sources.addonManagerKeyFile.sourcePath;
    };
    "controller-manager-cert-${machineName}" = {
      backendPath = "./certificates/kubernetes/certs/controller-manager-${machineName}.crt";
      linkPath = sources.controllerManagerCertFile.sourcePath;
      permissions = "444";
    };
    "controller-manager-key-${machineName}" = {
      backendPath = "./certificates/kubernetes/certs/controller-manager-${machineName}.key";
      linkPath = sources.controllerManagerKeyFile.sourcePath;
    };
    "scheduler-cert-${machineName}" = {
      backendPath = "./certificates/kubernetes/certs/scheduler-${machineName}.crt";
      linkPath = sources.schedulerCertFile.sourcePath;
      permissions = "444";
    };
    "scheduler-key-${machineName}" = {
      backendPath = "./certificates/kubernetes/certs/scheduler-${machineName}.key";
      linkPath = sources.schedulerKeyFile.sourcePath;
    };
    service-account = {
      backendPath = "./serviceAccount/sa.pub";
      linkPath = sources.saPubFile.sourcePath;
      permissions = "444";
    };
    service-account-key = {
      backendPath = "./serviceAccount/sa.key";
      linkPath = sources.saKeyFile.sourcePath;
    };
  };

  kubernetesSecrets = {
    ca-cert = {
      backendPath = "./certificates/kubernetes/ca/kubernetes.crt";
      # backendPath = "./certificates/kubernetes/intermediates/kubernetes-ca.crt";
      linkPath = sources.caCertFile.sourcePath;
      permissions = "555";
    };
    # ca-key = {
    #   backendPath = "./certificates/kubernetes/ca/kubernetes.key";
    #   # backendPath = "./certificates/kubernetes/intermediates/kubernetes-ca.key";
    #   linkPath = sources.caKeyFile.sourcePath;
    # };
    "kubelet-server-cert-${machineName}" = {
      backendPath = "./certificates/kubernetes/certs/kubelet-${machineName}.crt";
      linkPath = sources.kubeletCertFile.sourcePath;
      permissions = "444";
    };
    "kubelet-server-key-${machineName}" = {
      backendPath = "./certificates/kubernetes/certs/kubelet-${machineName}.key";
      linkPath = sources.kubeletKeyFile.sourcePath;
    };
  };
in
{
  etcd.file = (if isEtcdMember then etcdSecrets else { });
  kubernetes.file =
    (if isControlPlaneMember then controlPlaneSecrets else { })
    // (if isKubernetesMember then kubernetesSecrets else { });
}
