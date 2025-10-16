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
  ...
}:

let
  clientRequestPort = 2379;
  peerCommunicationPort = 2380;
  etcdList = if roles ? etcd && roles.etcd != [ ] then roles.etcd else roles.controlPlane;

  #############################
  # Helper Functions

  # Create URL from hostname and port
  mkUrl = port: address: "https://${address}:${toString port}";
  mkUrls = port: addresses: map (address: mkUrl port address) addresses;
in

{
  enable = builtins.any (node: node.machineName == this.machineName) etcdList;

  nodeName = this.machineName;
  # TODO: use serviceAddresses
  listening = {
    peers = mkUrls peerCommunicationPort [ "0.0.0.0" ];
    clients = mkUrls clientRequestPort [ "0.0.0.0" ];
  };

  advertiseClientUrls = mkUrls clientRequestPort [ this.fqdn ];
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
