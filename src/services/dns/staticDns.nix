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
  clusterlib,
  ...
}:
let
  # imports
  flatten = lib.lists.flatten;
  remove = lib.lists.remove;
  forEach = lib.lists.forEach;
  forEachAttrIn = clusterlib.forEachAttrIn;

  str = lib.types.str;
  attrsOf = lib.types.attrsOf;

  mkOption = lib.mkOption;

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
    ++ builtins.attrValues (
      forEachAttrIn config.services.staticDns.customEntries (hostName: ip: "${ip} ${hostName}")
    )
  );

  # merge the entrylist into a line separated string
  entries = (builtins.concatStringsSep "\n" entryList);

in
{

  options.services.staticDns.customEntries = mkOption {
    description = "A list of additional entries that should be added to the ``/etc/hosts`` file.";
    type = attrsOf str;
    default = { };
    example = {
      "example.com" = "127.0.0.1";
    };
  };

  config.networking.extraHosts = entries;
}
