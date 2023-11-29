{ config, lib, ... }: {
  options = with lib;
    with types; {
      k3s = {
        version = mkOption { type = str; };
        init = {
          ip = mkOption {
            type = nullOr str;
            default = null;
          };
        };
        server = {
          name = mkOption {
            type = nullOr str;
            default = null;
          };
          ip = mkOption {
            type = nullOr str;
            default = null;
          };
          manifests = mkOption {
            type = listOf path;
            default = [ ];
          };
          extraConfig = mkOption {
            type = nullOr path;
            default = null;
          };
        };
        agent = {
          name = mkOption {
            type = nullOr str;
            default = null;
          };
          ip = mkOption {
            type = nullOr str;
            default = null;
          };
        };
      };
    };
  imports = [
    ./admin.nix
    ./network.nix
    ./ssh.nix
    ./colmena.nix
    ./setup.nix
    ./partitioning.nix
  ];
}
