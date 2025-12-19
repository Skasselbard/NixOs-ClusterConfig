{
  lib,
  clusterConfig,
  kubeLib,
  ...
}:
let
  certificates = clusterConfig.clusters.this.services.kubernetes.certificates;

  defaultAccounts =
    {
      clusterConfig,
    }:
    let
      this = clusterConfig.clusters.this;
      kubernetes = this.services.kubernetes;

      # machines
      selected = kubernetes.selectors;
      controlPlaneMachines = kubeLib.getControlPlaneList kubernetes.roles;

      # Fqdns
      clusterFqdn = this.fqdn;
      etcdFqdns = kubeLib.getEtcdFqdns kubernetes.roles;
      controlPlaneFqdns = kubeLib.getControlPlaneFqdns kubernetes.roles;

      # Ips
      controlPlaneIps = kubeLib.getControlPlaneIps kubernetes.roles;
      etcdIps = kubeLib.getEtcdIps kubernetes.roles;
      virtualIps = kubernetes.virtualIps;

      # helpers
      forAllSelected = forAll selected;
      forControlPlane = forAll controlPlaneMachines;
      forAll =
        machines: accountName: accountBuilder:
        builtins.listToAttrs (
          map (machine: {
            name = "${accountName}-${machine.name}";
            value = (accountBuilder machine);
          }) machines
        );
    in
    {
      etcd = {

        ca = {
          roleName = "etcd-ca";
          expectedCertPath = certificates.etcd.caCertFile.targetPath;
          expectedKeyPath = certificates.etcd.caKeyFile.targetPath;
        };

        server = {
          roleName = "etcd-server";
          domains = [ "localhost" ] ++ etcdFqdns;
          ips = [ "127.0.0.1" ] ++ etcdIps;
          expectedCertPath = certificates.etcd.serverCertFile.targetPath;
          expectedKeyPath = certificates.etcd.serverKeyFile.targetPath;
        };

        peer = {
          roleName = "etcd-peer";
          domains = [ "localhost" ] ++ etcdFqdns;
          ips = [ "127.0.0.1" ] ++ etcdIps;
          expectedCertPath = certificates.etcd.peerCertFile.targetPath;
          expectedKeyPath = certificates.etcd.peerKeyFile.targetPath;
        };

      }
      // forControlPlane "apiserver-etcd-client" (machine: {
        roleName = "apiserver-etcd-client-${machine.name}";
        domains = [ machine.fqdn ];
        ips = [ ];
        expectedCertPath = certificates.apiServer.etcdClientCertFile.targetPath;
        expectedKeyPath = certificates.apiServer.etcdClientKeyFile.targetPath;
      });

      kubernetes = {

        ca = {
          roleName = "kubernetes-ca";
          expectedCertPath = certificates.caCertFile.targetPath;
          expectedKeyPath = certificates.caCertFile.targetPath;
        };

        super-admin = {
          roleName = "kubernetes-super-admin";
          kubernetesGroup = "system:masters";
          expectedCertPath = null;
          expectedKeyPath = null;
        };

        admin = {
          roleName = "kubernetes-admin";
          kubernetesGroup = "system:masters";
          expectedCertPath = null;
          expectedKeyPath = null;
        };

        apiserver = {
          roleName = "apiserver";
          domains = [
            "localhost"
            "kubernetes"
            "kubernetes.${clusterFqdn}"
          ]
          ++ controlPlaneFqdns;
          ips = [ "127.0.0.1" ] ++ controlPlaneIps ++ virtualIps;
          expectedCertPath = certificates.apiServer.certFile.targetPath;
          expectedKeyPath = certificates.apiServer.keyFile.targetPath;
        };

        addon-manager = {
          roleName = "addon-manager";
          kubernetesGroup = "system:masters";
          expectedCertPath = certificates.addonManagerCertFile.targetPath;
          expectedKeyPath = certificates.addonManagerKeyFile.targetPath;
        };

      }

      // forAllSelected "kubelet" (machine: {
        roleName = "system:node:${machine.fqdn}"; # Must match kubelet name
        kubernetesGroup = "system:nodes";
        domains = [ machine.fqdn ];
        ips = [ ];
        expectedCertPath = certificates.kubeletCertFile.targetPath;
        expectedKeyPath = certificates.kubeletKeyFile.targetPath;
      })

      // forControlPlane "apiserver-kubelet-client" (machine: {
        roleName = "kube-apiserver-kubelet-client-${machine.name}";
        kubernetesGroup = "system:masters";
        domains = [ ];
        ips = [ ];
        expectedCertPath = certificates.apiServer.kubeletClientCertFile.targetPath;
        expectedKeyPath = certificates.apiServer.kubeletClientKeyFile.targetPath;
      })

      // forControlPlane "controller-manager" (machine: {
        roleName = "system:kube-controller-manager";
        domains = [ ];
        ips = [ ];
        expectedCertPath = certificates.controllerManagerCertFile.targetPath;
        expectedKeyPath = certificates.controllerManagerKeyFile.targetPath;
      })

      // forControlPlane "scheduler" (machine: {
        roleName = "system:kube-scheduler";
        domains = [ ];
        ips = [ ];
        expectedCertPath = certificates.schedulerCertFile.targetPath;
        expectedKeyPath = certificates.schedulerKeyFile.targetPath;
      });
    };

in
defaultAccounts { inherit clusterConfig; }
