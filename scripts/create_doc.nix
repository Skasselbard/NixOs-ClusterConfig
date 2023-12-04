{ pkgs ? import <nixpkgs> { }, lib ? import <nixpkgs/lib>, ... }:
with builtins;
with lib;
let
  # lib = pkgs.lib;
  # evaluate our options
  eval = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    baseModules = [
      ../modules
      {
        # options.disko = lib.mkOption { type = lib.types.attrs; };
        config = {
          _module = {
            args = { inherit pkgs; };
            check = false;
          };
          # documentation.nixos.options.warningsAreErrors = false;
        };
      }
    ];
    modules = [ ];
  };
  docs = pkgs.nixosOptionsDoc { options = eval.options; };
in pkgs.runCommand "options-doc.md" { } ''
  cat ${docs.optionsCommonMark} | sed 's@file:///.*/NixOs-Staged-Hive/@'"../"'@g' | sed 's@/.*/NixOs-Staged-Hive/@'"NixOs-Staged-Hive/"'@g' >> $out
''
#lib.path.removePrefix lib.path.subpath.components lib.path.subpath.join
