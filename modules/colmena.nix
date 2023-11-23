{ lib, config, pkgs, ... }:

with lib;
with pkgs;
with builtins; {
  options = with types; {
    colmena.deployment = {
      targetHost = mkOption {
        type = nullOr str;
        default = null;
      };
    };
  };
}
