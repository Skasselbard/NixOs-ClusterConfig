{ lib }:
let
  remove = lib.lists.remove;
  flatten = lib.lists.flatten;

  # Create URL from hostname and port
  mkUrl = port: address: "https://${address}:${toString port}";
  mkUrls = port: addresses: map (address: mkUrl port address) addresses;

  getEtcdList = roles: if roles ? etcd && roles.etcd != [ ] then roles.etcd else roles.controlPlane;
  getControlPlaneList = roles: roles.controlPlane;

  getControlPlaneIps =
    roles: flatten (map (machine: parseRealIps machine.ips) (getControlPlaneList roles));
  getControlPlaneFqdns = roles: (map (node: node.fqdn) (getControlPlaneList roles));

  getEtcdIps = roles: flatten (map (machine: parseRealIps machine.ips) (getEtcdList roles));
  getEtcdFqdns = roles: (map (node: node.fqdn) (getEtcdList roles));

  # get a list of ips excluding dhcp configurations
  parseRealIps =
    ips:
    let
      ipList = flatten (lib.attrsets.mapAttrsToList (name: value: value) ips);
    in
    remove "dhcp" ipList;

in
{
  inherit
    mkUrl
    mkUrls

    getEtcdList
    getEtcdIps
    getEtcdFqdns

    getControlPlaneList
    getControlPlaneIps
    getControlPlaneFqdns
    ;
}
