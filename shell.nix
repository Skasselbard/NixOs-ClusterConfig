# { pkgs ? import (import ./nixpkgs.nix) { } }:
{ pkgs ? import <nixpkgs> { }, ... }:
let
  staged-hive = pkgs.writeShellScriptBin "staged-hive" ''
    ${pkgs.python3}/bin/python3 scripts/hive.py ''${@:1}
  '';
in pkgs.mkShell {
  buildInputs = with pkgs; [
    colmena
    k3s
    python3
    nixos-generators
    nixfmt
    git
    coreutils
    # scripts
    staged-hive
  ];
  packages = let python-packages = ps: with ps; [ jinja2 pathlib2 ];
  in [ (pkgs.python3.withPackages python-packages) ];
}
