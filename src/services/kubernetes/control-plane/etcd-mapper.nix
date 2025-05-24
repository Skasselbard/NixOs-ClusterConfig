{
  clusterInfo,
  selectors,
  roles,
  this,
}:
{
  config,
  lib,
  pkgs,
  ...
}:

#####################

# clusterInfo: {
#   fqdn = "example.com";
#   machines = {
#     vm0 = {
#       annotations = {
#         clusterName = "example";
#         fqdn = "vm0.example.com";
#         ips = {};
#         machineName = "vm0";
#         serviceAddresses = [];
#       };
#       deployment = {
#         allowLocalDeployment = false;
#         buildOnTarget = false;
#         formatScript = null;
#         keys = {};
#         privilegeEscalationCommand = [];
#         replaceUnknownProfiles = true;
#         tags = [];
#         targetHost = "192.168.122.200";
#         targetPort = null;
#         targetUser = "root";
#       };
#       nixosConfiguration = {
#         _module = {};
#         _type = "configuration";
#         class = "nixos";
#         config = {};
#         extendModules = <function>;
#         extraArgs = {};
#         lib = {};
#         options = {};
#         pkgs = {};
#         type = {};
#       };
#       nixosModules = [
#         {}
#         {}
#         {}
#         {}
#         <function, args: {config, lib, pkgs, utils}>
#         {}
#         <function, args: {config, pkgs}>
#         <function, args: {config, extendModules, lib, pkgs}>
#         <function, args: {config}>
#       ];
#       serviceAddresses = [ ];
#       services = {
#         dns = {};
#         kubernetes = {};
#         secrets = {};
#       };
#       system = "x86_64-linux";
#       users = { };
#       virtualization = { };
#     };
#     vm1 = {
#       annotations = {
#         clusterName = "example";
#         fqdn = "vm1.example.com";
#         ips = {};
#         machineName = "vm1";
#         serviceAddresses = [];
#       };
#       deployment = {
#         allowLocalDeployment = false;
#         buildOnTarget = false;
#         formatScript = null;
#         keys = {};
#         privilegeEscalationCommand = [];
#         replaceUnknownProfiles = true;
#         tags = [];
#         targetHost = "192.168.122.201";
#         targetPort = null;
#         targetUser = "root";
#       };
#       nixosConfiguration = {
#         _module = {};
#         _type = "configuration";
#         class = "nixos";
#         config = {};
#         extendModules = <function>;
#         extraArgs = {};
#         lib = {};
#         options = {};
#         pkgs = {};
#         type = {};
#       };
#       nixosModules = [
#         {}
#         {}
#         {}
#         {}
#         <function, args: {config, lib, pkgs, utils}>
#         {}
#         <function, args: {config, pkgs}>
#         <function, args: {config, extendModules, lib, pkgs}>
#       ];
#       serviceAddresses = [ ];
#       services = {
#         dns = {};
#         kubernetes = {};
#         secrets = {};
#       };
#       system = "x86_64-linux";
#       users = { };
#       virtualization = { };
#     };
#     vm2 = {
#       annotations = {
#         clusterName = "example";
#         fqdn = "vm2.example.com";
#         ips = {};
#         machineName = "vm2";
#         serviceAddresses = [];
#       };
#       deployment = {
#         allowLocalDeployment = false;
#         buildOnTarget = false;
#         formatScript = null;
#         keys = {};
#         privilegeEscalationCommand = [];
#         replaceUnknownProfiles = true;
#         tags = [];
#         targetHost = "192.168.122.202";
#         targetPort = null;
#         targetUser = "root";
#       };
#       nixosConfiguration = {
#         _module = {};
#         _type = "configuration";
#         class = "nixos";
#         config = {};
#         extendModules = <function>;
#         extraArgs = {};
#         lib = {};
#         options = {};
#         pkgs = {};
#         type = {};
#       };
#       nixosModules = [
#         {}
#         {}
#         {}
#         {}
#         <function, args: {config, lib, pkgs, utils}>
#         {}
#         <function, args: {config, pkgs}>
#         <function, args: {config, extendModules, lib, pkgs}>
#       ];
#       serviceAddresses = [ ];
#       services = {
#         dns = {};
#         kubernetes = {};
#         secrets = {};
#       };
#       system = "x86_64-linux";
#       users = { };
#       virtualization = { };
#     };
#   };
#   services = {
#     dns = {
#       annotations = {
#         roles = {};
#         selectors = [];
#       };
#       definition = <function, args: {clusterInfo, roles, selectors, this}>;
#       extraConfig = { };
#       roles = {
#         hosts = [];
#       };
#       selectors = [
#         <function>
#       ];
#     };
#     kubernetes = {
#       annotations = {
#         roles = {};
#         selectors = [];
#       };
#       definition = <function, args: {clusterInfo, roles, selectors, this}>;
#       extraConfig = {
#         services = {};
#       };
#       roles = {
#         controlPlane = [];
#         worker = [];
#       };
#       selectors = [
#         <function>
#       ];
#     };
#     secrets = {
#       annotations = {
#         roles = {};
#         selectors = [];
#       };
#       definition = <function, args: {clusterInfo, roles, selectors, this}>;
#       extraConfig = { };
#       roles = { };
#       selectors = [
#         <function>
#       ];
#     };
#   };
#   users = {
#     admin = {
#       homeManagerModules = [
#         {}
#         {}
#       ];
#       systemConfig = {
#         extraGroups = [];
#         hashedPassword = "$6$60vBYZVRuV8HwUQI$K8nOgQgVQcNnlku3MBGMoAMU4o5heXCg2CPaX3/4InSJCTeJgqU3bPEF2.hibMY0tOx8dHNGE61lqEe.Rchxa/";
#         isNormalUser = true;
#         openssh = {};
#       };
#     };
#     root = {
#       homeManagerModules = [
#         {}
#       ];
#       systemConfig = {
#         extraGroups = [];
#         hashedPassword = "$6$gV1emEujFxua0zY1$4gq.RTxDX8EY30vIL1PSk4Qa9xJVxbP5.Dz87t0yElZRyFGaDyN8SF35lMofZ7OTGuKRGxyUSEBpYY/2BKQvj/";
#         openssh = {};
#       };
#     };
#   };
# }

# selectors: [
#   {
#     clusterName = "example";
#     fqdn = "vm0.example.com";
#     ips = {
#       eth0 = [
#         "192.168.122.200"
#       ];
#       eth1 = [
#         "dhcp"
#       ];
#     };
#     machineName = "vm0";
#     serviceAddresses = [ ];
#   }
#   {
#     clusterName = "example";
#     fqdn = "vm1.example.com";
#     ips = {
#       eth0 = [
#         "192.168.122.201"
#       ];
#       eth1 = [
#         "dhcp"
#       ];
#     };
#     machineName = "vm1";
#     serviceAddresses = [ ];
#   }
#   {
#     clusterName = "example";
#     fqdn = "vm2.example.com";
#     ips = {
#       eth0 = [
#         "192.168.122.202"
#       ];
#       eth1 = [
#         "dhcp"
#       ];
#     };
#     machineName = "vm2";
#     serviceAddresses = [ ];
#   }
# ]

# roles: {
#   controlPlane = [
#     {
#       clusterName = "example";
#       fqdn = "vm0.example.com";
#       ips = {
#         eth0 = [];
#         eth1 = [];
#       };
#       machineName = "vm0";
#       serviceAddresses = [ ];
#     }
#     {
#       clusterName = "example";
#       fqdn = "vm1.example.com";
#       ips = {
#         eth0 = [];
#         eth1 = [];
#       };
#       machineName = "vm1";
#       serviceAddresses = [ ];
#     }
#     {
#       clusterName = "example";
#       fqdn = "vm2.example.com";
#       ips = {
#         eth0 = [];
#         eth1 = [];
#       };
#       machineName = "vm2";
#       serviceAddresses = [ ];
#     }
#   ];
#   worker = [ ];
# }

# this: {
#   clusterName = "example";
#   fqdn = "vm0.example.com";
#   ips = {
#     eth0 = [
#       "192.168.122.200"
#     ];
#     eth1 = [
#       "dhcp"
#     ];
#   };
#   machineName = "vm0";
#   serviceAddresses = [ ];
# }
######################
let
  etcdList = if roles ? etcd && roles.etcd != [ ] then roles.etcd else roles.controlPlane;

  #############################
  # Helper Functions

  # Create URL from hostname and port
  mkUrl = port: address: "https://${address}:${toString port}";
  mkUrls = port: addresses: map (address: mkUrl port address) addresses;
in

{
  enable = builtins.any (node: node.machineName == this.machineName) etcdList;

  nodeName = this.machineName;
  # TODO: use serviceAddresses
  listening = {
    peers = mkUrls 2380 [ "0.0.0.0" ];
    clients = mkUrls 2379 [ "0.0.0.0" ];
  };

  advertiseClientUrls = mkUrls 2379 [ this.fqdn ];
  initialAdvertisePeerUrl = mkUrl 2380 this.fqdn;

  allNodes = map (node: {
    name = node.machineName;
    hostnames = [ node.fqdn ];
    initialAdvertisePeerUrl = mkUrl 2380 node.fqdn;
  }) etcdList;

}
