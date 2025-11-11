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
  kubeLib = import ./kubelib.nix { inherit lib; };

  flatten = lib.lists.flatten;
  forEach = lib.lists.forEach;

  cfg = config.services.kubernetes.cluster;

  keepalivedNodeList = kubeLib.getControlPlaneList roles;

  # parse annotations and raise errors for misconfigurations
  keepalivedAnnotations = lib.listToAttrs (
    map (
      node:
      let
        interfaceError = throw "Missing 'kubernetes.keepalived.virtualIpInterface' annotation for node ${node.machineName}";
        cfg = node.kubernetes.keepalived;
        interface =
          if lib.hasAttr "virtualIpInterface" cfg then
            if cfg.virtualIpInterface != null && cfg.virtualIpInterface != "" then
              cfg.virtualIpInterface
            else
              interfaceError
          else
            interfaceError;
      in
      {
        name = node.machineName;
        value = {
          priority = if cfg ? priority then cfg.priority else null;
          virtualIpInterface = interface;
        };
      }
    ) keepalivedNodeList
  );

  # find and assign keepalived priorities
  # either used annotations or assign free priorities in descending order
  assignKeepalivedPriorities =
    let
      usedPriorities = lib.filter (p: p != null) (
        map (n: keepalivedAnnotations.${n.machineName}.priority or null) keepalivedNodeList
      );

      # Generate descending range of 255..0
      descending = lib.reverseList (lib.range 0 255);

      freePriorities = lib.filter (p: !(lib.elem p usedPriorities)) descending;

      # Recursive helper to assign priorities in order
      assign =
        nodes: free: remaining:
        if nodes == [ ] then
          { }
        else
          let
            node = builtins.head nodes;
            rest = builtins.tail nodes;
            nodeName = node.machineName;
            current = keepalivedAnnotations.${nodeName}.priority or null;
            # use existing or first free priority
            newPriority = if current != null then current else builtins.head remaining;
            nextRemaining = if current != null then remaining else builtins.tail remaining;
          in
          {
            ${nodeName} = (keepalivedAnnotations.${nodeName} or { }) // {
              priority = newPriority;
            };
          }
          // (assign rest free nextRemaining);
    in
    assign keepalivedNodeList freePriorities descending;

  priority = assignKeepalivedPriorities."${this.machineName}".priority;
  interface = assignKeepalivedPriorities."${this.machineName}".virtualIpInterface;
  virtualIps = map (ip: { addr = ip; }) cfg.virtualIps;

  hostsEntryList = flatten (
    forEach cfg.virtualIps (ip: "${ip} kubernetes.${clusterInfo.fqdn} kubernetes k8s")
  );
  hostsEntries = (builtins.concatStringsSep "\n" hostsEntryList);

in
{

  services.keepalived = {
    enable = config.services.kubernetes.apiserver.enable;
    openFirewall = true;

    vrrpInstances.kubernetes = {
      inherit
        interface
        priority
        virtualIps
        ;

      virtualRouterId = priority;
      trackInterfaces = [ interface ];

      # setup authentication to avoid listening to conflicting multicast messages
      extraConfig = ''
        authentication {
              auth_type PASS
              auth_pass ${clusterInfo.fqdn}
        }
      '';
    };
  };

  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = lib.mkDefault true;
  boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkDefault true;

  # Adds the virtual Ips to the hosts file with the hostnames: 'kubernetes.${clusterInfo.fqdn}', 'kubernetes' and 'k8s'
  # Does only work with the first ip from the virtual ip list
  networking.extraHosts =
    if config.services.keepalived.enable then hostsEntries else lib.mkDefault "";
}
