{ config, lib, ... }: {
  options = with lib;
    with types; {
      k3s = {
        version = mkOption {
          type = str;
          description = lib.mdDoc "FIXME: depricated; should be removed";
        };
        init = {
          ip = mkOption {
            type = nullOr str;
            default = null;
            description = lib.mdDoc "null";
          };
        };
        server = {
          name = mkOption {
            type = nullOr str;
            default = null;
            description = lib.mdDoc "null";
          };
          ip = mkOption {
            type = nullOr str;
            default = null;
            description = lib.mdDoc "null";
          };
          manifests = mkOption {
            type = listOf path;
            default = [ ];
            description = lib.mdDoc "null";
          };
          extraConfig = mkOption {
            type = nullOr path;
            default = null;
            description = lib.mdDoc "null";
          };
        };
        agent = {
          name = mkOption {
            type = nullOr str;
            default = null;
            description = lib.mdDoc "null";
          };
          ip = mkOption {
            type = nullOr str;
            default = null;
            description = lib.mdDoc "null";
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
