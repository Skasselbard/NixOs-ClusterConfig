# { pkgs ? import (import ./nixpkgs.nix) { } }:
{ pkgs ? import <nixpkgs> { }, ... }:
let
  staged-hive = pkgs.writeShellScriptBin "staged-hive" ''
    ${pkgs.python3}/bin/python3 scripts/hive.py ''${@:1}
  '';
  doc = pkgs.writeShellScriptBin "doc" ''
    cat $(${pkgs.nix}/bin/nix-build scripts/create_doc.nix | tail -n 1) > doc/options.md
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
    doc
  ];
  packages = let python-packages = ps: with ps; [ jinja2 pathlib2 ];
  in [ (pkgs.python3.withPackages python-packages) ];
}
