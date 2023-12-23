{
  description = "A very basic flake"; # TODO:

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    disko.url = "github:nix-community/disko/v1.1.0";
    colmena.url = "github:zhaofengli/colmena/v0.4.0";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    # let pkgs = import nixpkgs { }; in 
    {
      packages.x86_64-linux =
        with import nixpkgs { system = "x86_64-linux"; }; {
          default = pkgs.writeScriptBin "staged-hive"
            "${pkgs.nushell}/bin/nu ${self}/scripts/hive.nu \${@:1}";
          generation = pkgs.writeScriptBin "hive-generate"
            "${pkgs.nushell}/bin/nu ${self}/scripts/generate.nu \${@:1}";
        };
      apps.x86_64-linux = with import nixpkgs { system = "x86_64-linux"; }; {
        generation = {
          type = "app";
          program = "${self.packages.${system}.generation}/bin/hive-generate";
        };
      };
      nixosModules = {
        default = { config, ... }: { imports = [ "${self}/modules" ]; };
        iso = import "${self}/modules/iso.nix";
      };
    };
}
