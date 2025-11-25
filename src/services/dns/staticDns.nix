{
  config,
  lib,
  ...
}:
let
  # imports
  flatten = lib.lists.flatten;
  remove = lib.lists.remove;
  forEach = lib.lists.forEach;

  # get the service config
  cfg = config.clusterConfig.clusters.this.services.dns;

  # Get the hosts role from our service
  # Information about all machines that are assigned to this role in our cluster can be found here
  # TODO: hosts from other clusters could be added as well
  hosts = cfg.roles.hosts;

  # get a list of ips excluding dhcp configurations
  parseRealIps =
    ips:
    let
      ipList = flatten (lib.attrsets.mapAttrsToList (name: value: value) ips);
    in
    remove "dhcp" ipList;

  # transform the hosts into host-file entries
  entryList = flatten (
    forEach hosts (host: forEach (parseRealIps host.ips) (ip: "${ip} ${host.name} ${host.fqdn}"))
    # ++ builtins.attrValues (forEachAttrIn cfg.customEntries (hostName: ip: "${ip} ${hostName}"))
  );

  # merge the entry list into a line separated string
  entries = (builtins.concatStringsSep "\n" entryList);

in
{
  config.networking.extraHosts = entries;
}
