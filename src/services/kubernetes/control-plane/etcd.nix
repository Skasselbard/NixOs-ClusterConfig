{
  config,
  lib,
  resources,
  resourcesByRole,
  self,
  ...
}:
let
  cfg = config.services.kubernetes.cluster;

  nodeName = "vm0";
  controlPlaneNodes = [
    {
      name = "vm0";
      hostnames = [
        "vm0.internal"
        "localhost"
      ];
      listening = {
        peers = [ "0.0.0.0" ];
        clients = [ "0.0.0.0" ];
      };
    }
    # {
    #   name = "cp2";
    #   hostnames = [ "cp2.internal" ];
    #   advertiseHostname = "cp2.internal";
    # }
    # {
    #   name = "cp3";
    #   hostnames = [ "cp3.internal" ];
    # }
  ];

  #############################
  # Helper Functions

  thisNode = lib.findFirst (n: n.name == nodeName) null controlPlaneNodes;

  assertThisNode =
    if thisNode == null then throw "Node '${nodeName}' not found in controlPlaneNodes" else thisNode;

  # Determine advertise hostname
  advertiseHostname =
    if assertThisNode ? advertiseHostname then
      assertThisNode.advertiseHostname
    else if (builtins.length assertThisNode.hostnames) > 0 then
      builtins.elemAt assertThisNode.hostnames 0
    else
      throw "Node '${nodeName}' has no hostnames and no advertiseHostname";

  # Compose initial cluster string
  initialCluster = map (
    n:
    let
      peerHost =
        if n ? advertiseHostname then
          n.advertiseHostname
        else if (builtins.length n.hostnames) > 0 then
          builtins.elemAt n.hostnames 0
        else
          throw "Node '${n.name}' missing both 'advertiseHostname' and 'hostnames'";
    in
    "${n.name}=${mkUrl 2380 peerHost}"
  ) controlPlaneNodes;

  # Create URL from hostname and port
  mkUrl = port: address: "https://${address}:${toString port}";
  mkUrls = port: addresses: map (address: mkUrl port address) addresses;
in
#############################
# TODO: mkif silf is in controlplane nodes
{
  networking.firewall.allowedTCPPorts = [
    2379
    2380
  ];

  services.etcd = {
    enable = true;

    name = nodeName;
    initialCluster = initialCluster;
    # initialClusterToken = "";
    advertiseClientUrls = mkUrls 2379 [ advertiseHostname ];
    initialAdvertisePeerUrls = mkUrls 2380 [ advertiseHostname ];
    listenClientUrls = mkUrls 2379 assertThisNode.listening.clients;
    listenPeerUrls = mkUrls 2380 assertThisNode.listening.peers;

    # TODO: discovery

    clientCertAuth = true;
    peerClientCertAuth = true;

    trustedCaFile = cfg.certificates.etcd.caCertFile;

    certFile = cfg.certificates.etcd.serverCertFile;
    keyFile = cfg.certificates.etcd.serverKeyFile;
  };

  systemd.services.etcd = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };
}
