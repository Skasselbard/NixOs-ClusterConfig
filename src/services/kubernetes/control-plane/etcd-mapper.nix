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
  enable = builtins.any (node: node.machineName == this.machineName) etcdList;

  firewallPorts =
    if (builtins.any (node: node.machineName == this.machineName) etcdList) then
      [ peerCommunicationPort ]
    else
      [ ];

  nodeName = this.machineName;

  listening = {
    peers = mkUrls peerCommunicationPort [ "0.0.0.0" ];
    clients = mkUrls clientRequestPort [ "127.0.0.1" ];
  };

  advertiseClientUrls = mkUrls clientRequestAdvertisementPort [ this.fqdn ];
  initialAdvertisePeerUrl = mkUrl peerCommunicationPort this.fqdn;

  allNodes = map (node: {
    name = node.machineName;
    hostnames = [ node.fqdn ];
    initialAdvertisePeerUrl = mkUrl peerCommunicationPort node.fqdn;
  }) etcdList;

  initialCluster = map (
    node: "${node.machineName}=${mkUrl peerCommunicationPort node.fqdn}"
  ) etcdList;

}
