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

let

  #imports

  head = builtins.head;
  tail = builtins.tail;
  lists = lib.lists;
  flatten = lists.flatten;
  remove = lists.remove;
  forEach = lists.forEach;

  str = lib.types.str;
  listOf = lib.types.listOf;
  enum = lib.types.enum;

  mkOption = lib.mkOption;
  mkEnableOption = lib.mkEnableOption;

  # helper functions

  # get a list of ips excluding dhcp cobfigurations
  parseRealIps =
    ips:
    let
      ipList = flatten (lib.attrsets.mapAttrsToList (name: value: value) ips);
    in
    remove "dhcp" ipList;

  get = {

    serviceAddresses =
      searchRole: host:
      (
        if host ? serviceAddresses then
          builtins.filter (elem: elem.role == searchRole) host.serviceAddresses
        else
          [ ]
      );

    otherServers = builtins.filter (server: server.fqdn != this.fqdn) selectors;

    serverIps =
      host:
      let
        server = head (builtins.filter (selected: selected.fqdn == host.fqdn) selectors); # selectors[host]
        isInt = input: (builtins.tryEval (lib.toInt input)).success;
        isV4Octet = input: if (isInt input) then ((lib.toInt input) <= 255) else false;
        isIpV4 = listener: builtins.all isV4Octet (lib.splitString "." listener.address);
        isAllInterfaces = listener: listener.address == "0.0.0.0";
      in
      remove "del" (
        flatten (
          forEach (get.listeners server) (
            listener:
            if isAllInterfaces listener then
              parseRealIps server.ips
            else if isIpV4 listener then
              listener.address
            else
              "del"
          )
        )
      );

    hostFqdn = host: "${host.machineName}.kubernetes.${clusterInfo.fqdn}";

    hostEndpoints =
      host: forEach (get.listeners host) (listener: "${get.hostFqdn host}:${toString listener.port}");

    hostsEntries = flatten (
      lists.forEach selectors (
        host: lists.forEach (get.serverIps host) (ip: "${ip} ${host.machineName} ${get.hostFqdn host}")
      )
    );

  };

in

{

  ##########################################################
  # Additional options for cluster configuration.
  # Other options are defined in the nixos service module for kubernetes.

  options.services.kubernetes.cluster = {

    clusterName = mkOption {
      type = str;
      default = "kubernetes." + clusterInfo.fqdn;
    };

    certificates = {

      organization = mkOption {
        type = str;
        description = "";
      };

      organizationUnit = mkOption {
        type = str;
        description = "";
      };

      country = mkOption {
        type = str;
        description = "";
      };

      province = mkOption {
        type = str;
        description = "";
      };

      locality = mkOption {
        type = str;
        description = "";
      };

      domain = mkOption {
        type = str;
        default = clusterInfo.fqdn;
        description = "";
      };

      issuer = mkOption {
        type = str;
        default =
          config.services.kubernetes.cluster.certificates.organizationUnit
          + "/"
          + config.services.kubernetes.cluster.certificates.organization;
        description = "";
      };

    };
  };

  ###############################################
  imports = [ ./certificates.nix ];

  config =

    let

      cfg = config.services.kubernetes;

    in

    {

      environment.systemPackages = with pkgs; [
        kubernetes
        certstrap
        openssl
      ];

      services.kubernetes = {
        masterAddress = "master.example.com";
        clusterCidr = "10.200.0.0/16";

        # kubelet = {
        #   enable = "isMaster";
        #   unschedulable = "isMaster";
        #   tlsKeyFile = "path";
        #   tlsCertFile = "path";
        #   nodeIp = "ip";
        #   # manifests
        #   # kubeconfig.caFile
        #   # kubeconfig.certFile
        #   # kubeconfig.keyFile
        #   kubeconfig.server = "apiserver";
        #   # hostname
        # };
      };
    };

}
