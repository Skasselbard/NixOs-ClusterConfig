{
  config,
  lib,
  pkgs,
  kubeLib,
  ...
}:

let
  cluster = config.clusterConfig.clusters.this;
  selectors = config.clusterConfig.clusters.this.services.kubernetes.selectors;
  roles = config.clusterConfig.clusters.this.services.kubernetes.roles;
  this = config.clusterConfig.clusters.this.machines.this;

  clientRequestPort = 2378; # haProxy handles client requests on 2379

  clientRequestAdvertisementPort = 2379;
  peerCommunicationPort = 2380;

  etcdList = kubeLib.getEtcdList roles;

  #############################
  # Helper Functions

  # Create URL from hostname and port
  mkUrl = kubeLib.mkUrl;
  mkUrls = kubeLib.mkUrls;
in

{
  enable = builtins.any (node: node.name == this.name) etcdList;

  firewallPorts =
    if (builtins.any (node: node.name == this.name) etcdList) then
      [ peerCommunicationPort ]
    else
      [ ];

  nodeName = this.name;

  listening = {
    peers = mkUrls peerCommunicationPort [ "0.0.0.0" ];
    clients = mkUrls clientRequestPort [ "127.0.0.1" ];
  };

  advertiseClientUrls = mkUrls clientRequestAdvertisementPort [ this.fqdn ];
  initialAdvertisePeerUrl = mkUrl peerCommunicationPort this.fqdn;

  allNodes = map (node: {
    name = node.name;
    hostnames = [ node.fqdn ];
    initialAdvertisePeerUrl = mkUrl peerCommunicationPort node.fqdn;
  }) etcdList;

  initialCluster = map (
    node: "${node.name}=${mkUrl peerCommunicationPort node.fqdn}"
  ) etcdList;

}
