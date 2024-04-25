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
    ./partitioning.nix
  ];
# TODO: Config layout
# node = {
#   name = "BOB";
#   hostid = "random123";
#   domainNames = {
#     "example.com" = [ config.node.iface1.eno1.ipv4 ];
#   };
#   iface = {
#     eno1 = {
#       ipv4 = "0.0.0.0";
#       ipv6 = ::;
#     };
#   };
# };
}
