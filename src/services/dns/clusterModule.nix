{ lib, ... }:
let

  str = lib.types.str;
  attrsOf = lib.types.attrsOf;

  mkOption = lib.mkOption;

in
{
  config.extensions.clusterServices.dns = {
    defaultModule = import ./staticDns.nix;
    roles = [ "hosts" ];

    options.customEntries = mkOption {
      description = "A list of additional entries that should be added to the ``/etc/hosts`` file.";
      type = attrsOf str;
      default = { };
      example = {
        "example.com" = "127.0.0.1";
      };
    };
  };
}
