{ selectors, roles, this }:
{ config, lib, pkgs, ... }:
with lib.lists;
let
  # Expect a hosts role 
  hosts = roles.hosts;

  # transform the hosts into hostfile entries
  entryList = flatten (forEach hosts (host:
    forEach host.ips.all (ip: "${ip} ${host.machineName} ${host.fqdn}")));

  # merge the entrylist into a line separated string
  entries = (builtins.concatStringsSep "\n" entryList);

in { networking.extraHosts = entries; }

