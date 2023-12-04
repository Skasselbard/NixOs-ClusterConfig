{ lib, config, ... }:
with lib; {
  options = with types; {

    ip = mkOption {
      type = str;
      example = ''"dhcp" or "192.168.0.1'';
      description =
        lib.mdDoc "TODO: describe the interplay with kubernetes module";
    };
    interface = mkOption {
      type = str;
      example = "ens1";
      description = lib.mdDoc ''
        Sets this interface to be used for network configuration.

        TODO:
      '';
    };
    gateway = mkOption {
      type = str;
      description = lib.mdDoc "TODO:";
    };
    subnet = mkOption {
      type = str;
      description = lib.mdDoc "TODO:";
    };
    netmask = mkOption {
      type = int;
      description = lib.mdDoc "TODO:";
    };
  };
  # TODO: include network only if kubernetes is included?
  config = with config; {
    networking = {
      macvlans.vlan1 = mkIf (ip != "dhcp") {
        interface = interface;
        mode = "bridge";
      };
      interfaces.vlan1 = mkIf (ip != "dhcp") {
        ipv4.addresses = [{
          address = ip;
          prefixLength = netmask;
        }];
      };
      defaultGateway = mkIf (ip != "dhcp") {
        address = gateway;
        interface = "vlan1";
      };
      interfaces."${interface}".useDHCP = mkIf (ip == "dhcp") true;
    };
  };
}
