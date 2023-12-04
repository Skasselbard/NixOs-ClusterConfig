{ pkgs ? import <nixpkgs> { }, lib ? import <nixpkgs/lib>, ... }:
with builtins;
with lib;
let
  eval = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    baseModules = [
      ../modules
      {
        config = {
          _module = {
            args = { inherit pkgs; };
            check = false;
          };
        };
      }
    ];
    modules = [ ];
  };
  docs = pkgs.nixosOptionsDoc { options = eval.options; };
in pkgs.runCommand "options-doc.md" { } ''
  cat ${docs.optionsCommonMark} | sed 's@file:///.*/NixOs-Staged-Hive/@'"../"'@g' | sed 's@/.*/NixOs-Staged-Hive/@'"NixOs-Staged-Hive/"'@g' >> $out
''
