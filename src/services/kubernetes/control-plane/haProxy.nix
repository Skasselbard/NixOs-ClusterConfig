{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:

let

  cfg = config.services.kubernetes.cluster;

  cluster = config.clusterConfig.clusters.this;
  selectors = config.clusterConfig.clusters.this.services.kubernetes.selectors;
  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;
  this = config.clusterConfig.clusters.this.machines.this;

  controlPlaneNodeList = kubeLib.getControlPlaneList roles;
  etcdNodeList = kubeLib.getEtcdList roles;

  enable = (builtins.any (node: node.name == this.name) controlPlaneNodeList);

  apiServerPortBackend = config.services.kubernetes.apiserver.securePort;
  apiServerPortFrontend = 6443;

  etcdClientPortBackend = 2378;
  etcdClientPortFrontend = 2379;

  firewallPorts =
    (
      if (builtins.any (node: node.name == this.name) controlPlaneNodeList) then
        [
          apiServerPortFrontend
        ]
      else
        [ ]
    )
    ++ (
      if (builtins.any (node: node.name == this.name) etcdNodeList) then
        [
          etcdClientPortFrontend
        ]
      else
        [ ]
    );

in
lib.mkIf enable {
  # Open firewall conditionally for etcd and api-server ports
  networking.firewall.allowedTCPPorts = firewallPorts;

  services.haproxy = {
    enable = true;
    config = ''
      global
        log /dev/log local0
        maxconn 4096
        daemon

      defaults
        log global
        mode tcp
        option tcplog
        timeout connect 5s
        timeout client  50s
        timeout server  50s

      frontend etcd_api
        bind *:${builtins.toString etcdClientPortFrontend}
        default_backend etcdServers

      frontend kubernetes_api
        bind *:${builtins.toString apiServerPortFrontend}
        default_backend apiservers

      backend etcdServers
        mode tcp
        balance roundrobin
        option tcp-check

        # Prefer the local etcd server)
        server local-etcd-client 127.0.0.1:${builtins.toString etcdClientPortBackend} check weight 100

        # Other control-plane nodes as backup
        ${lib.concatMapStringsSep "\n" (node: ''
          server ${node.name} ${node.fqdn}:${builtins.toString etcdClientPortFrontend} check weight 10
        '') etcdNodeList}

      backend apiservers
        mode tcp
        balance roundrobin
        option tcp-check

        # Prefer the local kube-apiserver (running on :${builtins.toString apiServerPortBackend})
        server local-kube-api 127.0.0.1:${builtins.toString apiServerPortBackend} check weight 100

        # Other control-plane nodes as backup
        ${lib.concatMapStringsSep "\n" (
          node:
          "server ${node.name} ${node.fqdn}:${builtins.toString apiServerPortFrontend} check weight 10"
        ) controlPlaneNodeList}
    '';
  };

}
