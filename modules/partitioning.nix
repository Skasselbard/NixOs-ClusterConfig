# partition with disko https://github.com/nix-community/disko

{ pkgs, config, lib, ... }:
let
  disko_source = builtins.fetchTarball
    "https://github.com/nix-community/disko/archive/master.tar.gz";
  # "https://github.com/nix-community/disko/archive/${config.partitioning.disko_version}.tar.gz";
  disko = import disko_source { inherit lib; };
  disko_module = "${disko_source}/module.nix";
in {
  options = with lib;
    with types; {
      partitioning = {
        disko_version = mkOption {
          type = str;
          default = "v1.1.0";
        };
        format_disko = mkOption {
          type = attrs; # TODO: can the type be loaded from disko?
          default = { };
          description =
            "This disko definitions will be used to build a formating script and for the systems mounting configuration";
        };
        additional_disko = mkOption {
          type = attrs; # TODO: can the type be loaded from disko?
          default = { };
          description =
            "This disko definitions will be used in addition to the formatting definition to build the whole disko definition for mounting configuration";
        };
      };
    };
  imports = [ ./setup.nix disko_module ];
  config = {
    setup.scripts = [
      # building a disko reformating script and adding it to the setup (iso) environment
      (pkgs.writeScriptBin "disko-format" (disko.disko {
        # disko.devices = config.partitioning.format_disks;
        disko = config.partitioning.format_disko;
      }) + /bin/disko-format)
    ];
    disko = config.partitioning.format_disko
      // config.partitioning.additional_disko;
  };
}
