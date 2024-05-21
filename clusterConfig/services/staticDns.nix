{ selectors, roles, this }:
{ config, lib, pkgs, ... }:
let
  # Expect a hosts role 
  hosts = roles.hosts;

  # transform a host to a hostfiles entry
  toEntry = host: host;
in {
  networking.extraHosts =
    lib.debug.traceSeqN 8 roles.hosts "192.168.0.1 lanlocalhost";
}

