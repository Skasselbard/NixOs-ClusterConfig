{
  description = "A very basic flake"; # TODO:

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixos-generators.url = "github:nix-community/nixos-generators/1.8.0";
    disko.url = "github:nix-community/disko/v1.1.0";
    colmena.url = "github:zhaofengli/colmena/v0.4.0";
  };

  outputs = { self, ... }@inputs: {

    packages = {
      disko = inputs.disko;
      staged-hive = { x = "sdfsa"; };
    };
  };
}
