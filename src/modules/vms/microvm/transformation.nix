# MicroVM transformation — evaluates VM NixOS configs and injects them
# into host machines' nixosModules as microvm.vms.<name>.evaluatedConfig entries.
#
# Also automatically adds microvm.host.enable = true to any machine
# that hosts VMs.
{
  lib,
  clusterlib,
  flakeInputs,
  ...
}:
let
  add = clusterlib.add;
  get = clusterlib.get;

  # Map the ClusterConfig-level microvm backend options to the
  # microvm.nix guest-side option set (which lives under config.microvm).
  # Prune all unset values so that the default values of microvm can apply.
  # Pruning is done recursively, so that attrsets that become empty because of the previous pruning step also are pruned.
  # NOTE: It may be that filtering for unset value is sufficient.
  mapBackendToMicrovmConfig =
    backend:
    let
      prune =
        value:
        if builtins.isAttrs value then
          let
            pruned = lib.mapAttrs (_: prune) value;
            filtered = lib.filterAttrs (
              k: v:
              # shaerNiXStore is a convenience option defined by the clusterConfig module and should not be given to the microvm config
              k != "shareNixStore"
              &&
                # prune attrs that cannot be evaluated, e.g. because they throw an error
                (builtins.tryEval v).success
              &&
                # prune null attrs
                v != null
              &&
                # prune empty attrsets (v = {};)
                (!builtins.isAttrs v || builtins.attrNames v != [ ])
              &&
                # prune empty lists (v = [];)
                (!builtins.isList v || v != [ ])
            ) pruned;
          in
          filtered

        else if builtins.isList value then
          builtins.filter (v: (builtins.tryEval v).success && v != null) (map prune value)

        else
          value;
    in
    prune backend.microvm;

  # Build a share definition for the host's /nix/store using 9p
  nixStoreShare = {
    source = "/nix/store";
    mountPoint = "/nix/.ro-store";
    tag = "ro-store";
    proto = "9p";
  };

  # Build a full guest module from the backend config
  buildVmModule =
    vm:
    let
    mvm = vm.backend.microvm or { };
    shareConfig = if mvm.shareNixStore or true then
      {
        shares = (mvm.shares or [ ]) ++ [ nixStoreShare ];
      }
    else
      { };
    in
    {
      microvm = mapBackendToMicrovmConfig vm.backend // shareConfig;
    };

  buildVmModules = vmConfig: [
    flakeInputs.microvm.nixosModules.microvm
    (buildVmModule vmConfig)
  ];
  
  
  buildHostModules = vmName: vmConfig: hostConfig: [
    flakeInputs.microvm.nixosModules.host
    {
      microvm.host.enable = true;
      microvm.vms.${vmName} = {
        autostart = vmConfig.autostart or true;
        restartIfChanged = vmConfig.restartIfChanged or true;
        evaluatedConfig = vmConfig.nixosConfiguration;
      };
    }
  ];

  hostTransformation = config:
    add.nixosModule config (
      clusterName: nodeName: nodeConfig:
      let
        vms = map (vm: 
          let
            hostResolution = get.vmHost (vm.value.host or "") config;
          in
          if hostResolution.machine == nodeName && hostResolution.cluster == clusterName then
            {name = vm.name; config = vm.value;}
          else
            null
        ) (lib.attrsToList config.domain.clusters."${clusterName}".vms);
       filteredVMs = builtins.filter (vm: vm != null) vms;
      in
      if filteredVMs == [ ] then
        # If its a node with no vms configured: add nothing
        [ ]
      else
        # If its a host, add all host vm configurations
        map (vm: buildHostModules vm.name vm.config nodeConfig) filteredVMs
    );

  vmTransformation = config:
    add.nixosModule config (
      clusterName: nodeName: nodeConfig:
      if nodeConfig?host then
        buildVmModules nodeConfig
      else
        []
    );

in
{
  inherit vmTransformation hostTransformation;
}
