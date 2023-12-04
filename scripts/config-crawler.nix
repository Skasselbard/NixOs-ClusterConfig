{ pkgs ? import <nixpkgs> { }, lib ? import <nixpkgs/lib>, host-definition
, disko_url, ... }:

let
  eval = (lib.evalModules {
    modules = [
      host-definition
      # Setting dummy values and downloading disko source to make the module system happy
      {
        config._module.check = false;
        config.nixpkgs.hostPlatform = "x86_64-linux";
        # options.disko = lib.mkOption { type = lib.types.attrs; };
        config._disko_source = builtins.fetchTarball disko_url;
      }
    ] ++ (import <nixpkgs/nixos/modules/module-list.nix>);
  });
in lib.attrsets.recursiveUpdate # combine hostid with rest of the config
(if (eval.config.networking.hostId != null) then {
  # hostId is needed for zfs partitioning
  networking.hostId = eval.config.networking.hostId;
} else
  { }) {
    admin = eval.config.admin;
    networking.hostName = eval.config.networking.hostName;
    interface = eval.config.interface;
    ip = eval.config.ip;
    setup = eval.config.setup;
    partitioning = eval.config.partitioning;
    colmena = eval.config.colmena;
    # gateway = config.networking.defaultGateway;
    # interfaces = config.networking.interfaces;
    # k3s = {
    #   init.ip
    #   server.ip
    #   server.name
    #   agent.ip
    #   agent.name
    #   version
    # }
    # nixos_version
    # targetHost
  }
