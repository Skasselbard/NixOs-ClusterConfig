{ lib, config, pkgs, ... }:

with lib;
with pkgs;
with builtins;
let
  colmena_options = import (builtins.fetchurl
    "https://raw.githubusercontent.com/zhaofengli/colmena/main/src/nix/hive/options.nix");
in {
  options = with types; {
    colmena.deployment = (colmena_options.deploymentOptions {
      inherit lib;
      name = "{hostname}";
    }).options.deployment;
  };
}
