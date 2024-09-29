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
with lib.lists;
let
  # Expect a hosts role 
  hosts = roles.hosts;

  # get a list of ips excluding dhcp cobfigurations
  parseRealIps =
    ips:
    let
      ipList = flatten (lib.attrsets.mapAttrsToList (name: value: value) ips);
    in
    remove "dhcp" ipList;

  # transform the hosts into hostfile entries
  entryList = flatten (
    forEach hosts (host: forEach (parseRealIps host.ips) (ip: "${ip} ${host.machineName} ${host.fqdn}"))
  );

  # merge the entrylist into a line separated string
  entries = (builtins.concatStringsSep "\n" entryList);

in
{
  networking.extraHosts = entries;
}
