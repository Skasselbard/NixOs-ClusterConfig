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
  cfg = config.services.kubernetes.cluster;
  mappedClusterConfig = (
    import ./etcd-mapper.nix
      {
        inherit
          clusterInfo
          selectors
          roles
          this
          ;
      }
      {
        inherit config lib pkgs;
      }
  );

  #############################
  # Helper Functions

  # thisNode = lib.findFirst (n: n.name == nodeName) null controlPlaneNodes;

  # assertThisNode =
  #   if thisNode == null then throw "Node '${nodeName}' not found in controlPlaneNodes" else thisNode;

  # # Determine advertise hostname
  # advertiseHostname =
  #   if assertThisNode ? advertiseHostname then
  #     assertThisNode.advertiseHostname
  #   else if (builtins.length assertThisNode.hostnames) > 0 then
  #     builtins.elemAt assertThisNode.hostnames 0
  #   else
  #     throw "Node '${nodeName}' has no hostnames and no advertiseHostname";

  # Compose initial cluster string
  initialCluster = map (
    node: "${node.name}=${node.initialAdvertisePeerUrl}"
  ) mappedClusterConfig.allNodes;

in
lib.mkIf mappedClusterConfig.enable {
  networking.firewall.allowedTCPPorts = [
    2379
    2380
  ];

  users.groups.etcd = { };
  users.users.etcd = {
    isNormalUser = false;
    isSystemUser = true;
    group = "etcd";
  };

  services.etcd = {
    enable = true;

    name = mappedClusterConfig.nodeName;
    initialCluster = initialCluster;
    # initialClusterToken = "";
    advertiseClientUrls = mappedClusterConfig.advertiseClientUrls;
    initialAdvertisePeerUrls = [ mappedClusterConfig.initialAdvertisePeerUrl ];
    listenClientUrls = mappedClusterConfig.listening.clients;
    listenPeerUrls = mappedClusterConfig.listening.peers;

    # TODO: discovery

    clientCertAuth = true;
    peerClientCertAuth = true;

    trustedCaFile = cfg.certificates.etcd.caCertFile.targetPath;

    certFile = cfg.certificates.etcd.serverCertFile.targetPath;
    keyFile = cfg.certificates.etcd.serverKeyFile.targetPath;
  };

  systemd.services.etcd = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };
}
