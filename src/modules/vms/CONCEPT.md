# VM Module for NixOsClusterConfig — Concept Document

## 1. Motivation & Vision

NixOsClusterConfig today models **physical (or standalone virtual) NixOS machines**. A machine has a `nixosConfiguration`, deployment scripts (`iso`, `create`, `deploy`), and appears in the colmena hive. This works well for machines that exist independently on the network.

**VMs** (virtual machines) are **guest systems that run on a host machine**, managed by a hypervisor. Their lifecycle is governed by the host's systemd units (e.g. `microvm@<name>.service`). They are not deployed via SSH — instead, their NixOS configuration is embedded into the host machine's configuration.

This module introduces a first-class `vms` concept parallel to `machines` within each cluster. It uses **microvm.nix** as the initial backend, with a clean abstraction layer that allows future backends like nixvirt and nspawn containers.

VMs participate in **all cluster features**: they can be targeted by cluster services (DNS, secrets, etc.) via filters, they contribute IPs to the cluster info, and they get cluster-level user definitions. This full integration is the reason VMs are a cluster-level module rather than just inline NixOS config on a host machine.

## 2. Architectural Position

```
cluster (e.g. "mycluster")
├── machines          ← physical / standalone NixOS nodes
│   ├── host1         ← hosts VMs
│   │   ├── system
│   │   ├── nixosModules
│   │   ├── deployment  (targetHost, formatScript, ...)
│   │   └── nixosConfiguration
│   ├── host2
│   └── ...
│
├── vms               ← NEW: virtual machines (guests)
│   ├── vm1
│   │   ├── system
│   │   ├── host       ← FQDN of the host machine (resolved to cluster path)
│   │   ├── nixosModules
│   │   ├── backend    ← backend-specific config
│   │   │   ├── type = "microvm"
│   │   │   └── microvm = {
│   │   │       hypervisor = "qemu";
│   │   │       vcpu = 2;
│   │   │       mem = 4096;
│   │   │       shareNixStore = true;
│   │   │       interfaces = [ ... ];
│   │   │       volumes = [ ... ];
│   │   │     }
│   │   └── nixosConfiguration  ← evaluated, injected into host config
│   ├── vm2
│   └── ...
│
├── users
└── services
```

## 3. Key Design Decisions

### 3.1 VMs are cluster elements, not machine sub-elements

VMs sit at the **same level as machines** inside a cluster (`domain.clusters.<name>.vms`), not nested under a host machine. Rationale:

- Cluster services can target VMs the same way they target machines (using filter expressions).
- A VM might migrate between hosts — the cluster still sees it.
- The `clusterConfig` representation can include VM data uniformly.
- This mirrors how real orchestration systems treat VMs and physical nodes uniformly.

### 3.2 The `host` binding uses FQDN, resolved by searching cluster config

Each VM declares a `host` attribute using a **fully qualified domain name** (FQDN), which is resolved by searching the cluster config for a matching `<machine>.<cluster>` pair:

```nix
vms.postgres-vm.host = "host1.example.com";   # full FQDN
# or
vms.postgres-vm.host = "host1.example";       # domain suffix auto-appended
```

#### Why FQDN?

- **Unambiguous**: The host is uniquely identified even when clusters have dots in their names (e.g. `"prod.kubernetes"`).
- **Self-documenting**: The FQDN tells you exactly which cluster the host belongs to.
- **Flexible naming**: Supports machine names like `"group-name.app-name"` and cluster names like `"prod.us-east"`.

#### Resolution algorithm

Rather than naively splitting on dots (which fails when names contain dots), the resolver **searches** for a valid `machine.cluster` pair:

```
Input:  "group-name.app-name.prod.us-east.example.com"
        Strip domain suffix ".com"
        → "group-name.app-name.prod.us-east.example"

Try all split points (walking from left to right, machine gets more parts):
  split at 1: machine="group-name"                    cluster="app-name.prod.us-east.example"
  split at 2: machine="group-name.app-name"           cluster="prod.us-east.example"
  split at 3: machine="group-name.app-name.prod"      cluster="us-east.example"
  split at 4: machine="group-name.app-name.prod.us-east"  cluster="example"

For each split, check:
  - Does config.domain.clusters."<cluster>" exist?
  - Does config.domain.clusters."<cluster>".machines."<machine>" exist?

The first matching split wins.
```

Examples:
| Input `host` | Domain suffix `.com` | Resolved pair |
|---|---|---|
| `host1.example.com` | `.com` | machine=`host1`, cluster=`example` |
| `host1.example` | `.com` | machine=`host1`, cluster=`example` |
| `myhost.prod.kubernetes.example.com` | `.com` | machine=`myhost`, cluster=`prod.kubernetes` |
| `app.db.prod.us-east.example` | `.com` | machine=`app.db`, cluster=`prod.us-east` |

The module validates at evaluation time that:
- Exactly one matching `<machine>.<cluster>` pair is found.
- The referenced machine exists in the referenced cluster.
- The host machine's `system` is compatible with the VM's virtualization backend.

If no match is found:
```
Error: VM 'postgres-vm' references host 'nonexistent.example.com' but
no matching machine.cluster pair was found in the cluster config.
Searched: domain.clusters.*.machines.nonexistent
```

### 3.3 Backend abstraction with type-discriminated submodule

Each VM has a `backend` attribute using a type-discriminated submodule:

```nix
vm.backend = {
  type = "microvm";    # discriminator
  microvm = { ... };   # backend-specific options (only when type == "microvm")
  # nixvirt = { ... };  # future
  # nspawn = { ... };   # future
};
```

This pattern:
- Keeps each backend's options namespaced, avoiding collision.
- Allows backends to have completely different option structures.
- Is extensible — adding a new backend means adding an enum value and a submodule.

### 3.4 Microvm options loaded directly from the microvm.nix flake

The microvm backend submodule **imports option definitions from the microvm.nix flake**, exactly like the colmena module imports colmena deployment options:

```nix
# In the cluster module:
microvmOptions = (import "${flakeInputs.microvm}/nixos-modules/microvm/options.nix");

# The backend submodule reuses these option types:
microvmSubmodule.options = {
  hypervisor = microvmOptions.microvm.hypervisor;
  vcpu = microvmOptions.microvm.vcpu;
  mem = microvmOptions.microvm.mem;
  # ... selective subset
};
```

This approach:
- **Stays in sync** with upstream microvm.nix option changes.
- **Reduces duplication** — no copied option definitions.
- **Leverages existing types** — e.g. `types.enum self-lib.hypervisors` from microvm.nix.

Not all microvm.nix options are exposed. Some are set automatically by the module (see section 3.5).

### 3.5 Automatically managed options — convenience, defaults, and validation

The module handles three categories of microvm.nix options:

#### Category A: Convenience options (new, not in microvm.nix)

These are ClusterConfig-specific options that translate to one or more microvm.nix options:

| ClusterConfig option | Maps to microvm.nix option(s) | Default |
|---|---|---|
| `shareNixStore` (bool) | `shares = [{ source = "/nix/store"; mountPoint = "/nix/.ro-store"; tag = "ro-store"; proto = "9p"; }]` | `false` |

When `shareNixStore = true`, the module automatically injects a 9p share of the host's `/nix/store` into the VM, making it available at `/nix/.ro-store`. The 9p protocol is chosen because it works out-of-the-box with qemu (the default hypervisor). This single boolean eliminates 6 lines of boilerplate per VM definition.

#### Category B: Forced options (set by the module, always)

These options are always set to a specific value by the module. If the user attempts to override them in `nixosModules`, the override is either silently accepted (standard NixOS module merging) or causes a validation warning:

| Option | Forced value | Reason |
|---|---|---|
| `microvm.guest.enable` | `true` | Always a guest when managed by ClusterConfig |
| `microvm.optimize.enable` | `true` | Always optimize for embedded use |
| `microvm.storeDiskType` | `"squashfs"` | Smaller images (can be overridden by user preference) |

#### Category C: Disallowed options (error if user sets)

These options are managed internally and must not be set by the user. Setting them in `nixosModules` causes an evaluation error with a clear message:

| Option | Reason disallowed |
|---|---|
| `microvm.declaredRunner` | Computed internally by microvm.nix |
| `microvm.runner` | Computed internally by microvm.nix |
| `microvm.binScripts` | Managed by the module for automation |
| `microvm.systemSymlink` | Set by the module |
| `microvm.vmHostPackages` | Set by the module (host's package set) |
| `microvm.kernelParams` | Managed internally |
| `microvm.hostName` | Derived from the VM's name in the cluster |

Validation is implemented as a NixOS module assertion or as a module that uses `lib.warnIf` / `lib.assertMsg` on the evaluated `config.microvm.*` values.

### 3.6 No deployment pipeline for VMs

VMs do **not** participate in the standard deployment pipeline:
- No `nixos-anywhere` / `create` / `iso` scripts per VM.
- No colmena hive entries.
- No `deployment` option block.

Instead, the VM's NixOS configuration is **injected into the host machine's NixOS modules**. The host's hypervisor module (e.g. microvm) creates the systemd service. Rebuilding and switching the host also updates the VM.

### 3.7 Automatic host configuration

When a VM is declared on a host machine, the module **automatically adds the required host configuration** to that machine's `nixosModules`. No manual setup needed:

```nix
# This is done automatically by the module:
host machine receives:
  {
    microvm.host.enable = true;
    # Potentially additional host-side config (networking, storage, etc.)
  }
```

The user **does not** need to add `microvm.host.enable = true` manually in the host's `nixosModules`. The module detects which machines host VMs and injects the necessary config.

### 3.8 VM IP discovery — identical to machines

VM IP discovery works **exactly the same way** as for machines. The pattern is:

1. The **backend** (microvm) defines the virtual network interface (tap, user, macvtap, bridge) — this is the virtual NIC.
2. The **VM's nixosModules** define the network configuration for that interface — this is where static IPs are set:

```nix
vms.postgres-vm = {
  backend.microvm.interfaces = [
    {
      type = "tap";
      id = "vm-postgres";
      mac = "02:00:00:00:00:10";
    }
  ];

  nixosModules = [
    {
      # Configure the virtual NIC — same pattern as a machine!
      networking.interfaces.eth0 = {
        ipv4.addresses = [{ address = "10.0.0.10"; prefixLength = 24; }];
      };
      services.postgresql.enable = true;
    }
  ];
};
```

The VM's NixOS config includes `networking.interfaces`, `networking.firewall`, etc. — just like a machine. When the VM's `nixosConfiguration` is evaluated, the standard `clusterlib.get.ips` function extracts IPs. These IPs flow into the `clusterConfig` representation and can be used by cluster services (DNS, monitoring, etc.).

**Differences from machines**: With machines, the physical interface exists on the hardware. With VMs, the interface is declared in the backend config AND configured in the NixOS config. The VM author is responsible for matching the interface name used in the backend (e.g. first interface = `eth0`, second = `eth1` by default on Linux) with the configuration in `nixosModules`.

### 3.9 Full participation in cluster features

VMs participate in **all** cluster config features that machines participate in:

| Feature | Machines | VMs |
|---|---|---|
| **Service selectors** | `selectors = [ filters.hostname "x" ]` | `selectors = [ filters.vmName "x" ]` |
| **Service roles** | `roles.primary = [ filters.hostname "x" ]` | `roles.primary = [ filters.vmName "x" ]` |
| **Cluster users** | Users applied to all machines | Users applied to all VMs |
| **DNS (simple-dns)** | Static IPs added to /etc/hosts | Static IPs added to /etc/hosts |
| **Secrets** | Per-machine secrets | Per-VM secrets |
| **clusterConfig representation** | `clusterConfig.clusters.this.machines.<name>` | `clusterConfig.clusters.this.vms.<name>` |
| **Filter functions** | `filters.hostname`, `filters.clusterMachines` | `filters.vmName`, `filters.clusterVms` |

This full integration is the **core value proposition** of VMs as a cluster module. Without it, VMs could simply be defined inline in a host machine's `nixosModules` using raw `microvm.vms` declarations.

## 4. Comparison: Machines vs. VMs

| Aspect | Machine | VM |
|---|---|---|
| **Lifecycle** | Independent; deployed via SSH | Managed by host; started/stopped via systemd |
| **Deployment** | nixos-anywhere, colmena | Injected into host's NixOS config |
| **Network** | Physical or virtual NIC, own IP | Virtual NIC declared in backend, IP configured in nixosModules |
| **IP discovery** | `get.ips` from `nixosConfiguration` | Same mechanism — `get.ips` from VM's `nixosConfiguration` |
| **system** | Required (e.g. `x86_64-linux`) | Required |
| **nixosModules** | Required | Required (guest configuration + network config) |
| **host** | N/A (implicitly self-hosted) | FQDN resolving to a cluster machine path |
| **deployment.targetHost** | Required | N/A |
| **deployment.formatScript** | Optional | N/A |
| **serviceAddresses** | Supported | Supported (same mechanism via IP extraction) |
| **users** | Cluster + machine level | Cluster level + possible future per-VM level |
| **packages** | `build`, `deploy`, `create`, `iso`, `format` | `build` only |
| **colmena entry** | Yes | No |
| **Backend config** | N/A | Required (type + backend-specific options) |
| **Auto host config** | N/A | `microvm.host.enable = true` added automatically |

## 5. Option Structure

### 5.1 Cluster-level option

```nix
# In domain.clusters.<name>:
vms = mkOption {
  description = "Virtual machines running on cluster hosts.";
  type = attrsOf (submodule vmType);
  default = {};
};
```

### 5.2 VM type (`vmType`)

```nix
vmType.options = {
  system = mkOption {
    description = "System architecture for this VM.";
    type = str;
    example = "x86_64-linux";
  };

  host = mkOption {
    description = ''
      FQDN of the cluster machine that hosts this VM.

      Must resolve to an existing machine in the cluster config.
      Accepted forms:
        - "host1.example.com"  (full FQDN with domain suffix)
        - "host1.example"      (without domain suffix — suffix auto-appended)

      The resolver searches for a matching <machine>.<cluster> pair by trying
      all possible split points. See section 3.2 for the algorithm.
    '';
    type = str;
    example = "host1.example.com";
  };

  nixosModules = mkOption {
    description = "NixOS modules for the VM's guest configuration.";
    type = listOf raw;
    default = [];
  };

  users = mkOption {
    description = ''
      Per-VM user definitions, same structure as machine-level users.
      These are merged with cluster-level users during evaluation.
    '';
    type = attrsOf (submodule userType);
    default = {};
  };

  # ── Lifecycle (cross-backend, host-side) ──

  autostart = mkOption {
    description = ''
      Whether to start this VM automatically at host boot.

      Maps to microvm.autostart (or equivalent in future backends).
      When true, the VM is added to the host's microvms.target.
    '';
    type = bool;
    default = true;
  };

  restartIfChanged = mkOption {
    description = ''
      Whether to restart this VM's systemd services when the host
      is rebuilt and the VM configuration changes.

      Maps to microvm.vms.<name>.restartIfChanged (or equivalent).
    '';
    type = bool;
    default = true;
  };

  # ── Backend ──

  backend = mkOption {
    description = "Virtualization backend configuration.";
    type = submodule backendType;
  };
};
```

### 5.2a The `users` option for VMs

VMs support per-VM users, exactly like machines support per-machine users. The `userType` is the same shared type used by both machines and VMs:

```nix
vms.web-vm.users.myuser = {
  systemConfig = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
  homeManagerModules = [ ... ];  # if home-manager module is loaded
};
```

Cluster-level users are applied to all VMs; per-VM users are additive. This mirrors the cluster-users + machine-users pattern exactly.

### 5.2b Why `autostart` and `restartIfChanged` live on `vmType`

These two options control the VM's **host-side lifecycle** — when it starts and whether it restarts — and are universal across all backends (microvm, nixvirt, nspawn). They map to `microvm.vms.<name>.autostart` / `microvm.vms.<name>.restartIfChanged` in the microvm backend, and will have equivalents in future backends.

Backend-specific evaluation controls (`pkgs`, `nixpkgs`, `specialArgs`, `extraModules`) live inside the backend submodule (see section 5.4 MicroVM submodule), not on `vmType`. This keeps the `vmType` clean while still giving users direct access to lifecycle behavior without having to navigate backend-specific namespaces.

### 5.3 Backend type (`backendType`)

```nix
backendType.options = {
  type = mkOption {
    description = "Virtualization backend to use.";
    type = enum [
      "microvm"
      # future: "nixvirt", "nspawn"
    ];
    default = "microvm";
  };

  microvm = mkOption {
    description = "MicroVM-specific configuration.";
    type = submodule microvmSubmodule;
    default = {};
  };

  # Future backends:
  # nixvirt = mkOption { type = submodule nixvirtSubmodule; default = {}; };
  # nspawn = mkOption { type = submodule nspawnSubmodule; default = {}; };
};
```

### 5.4 MicroVM submodule (`microvmSubmodule`)

This submodule **imports option definitions from the microvm.nix flake** (similar to how colmena options are imported in `src/deployment.nix`). The following are ClusterConfig-level options that control the VM's hypervisor configuration.

#### Core options (imported from microvm.nix)

```nix
microvmSubmodule.options = {
  # ── Convenience (ClusterConfig-specific) ──

  shareNixStore = mkOption {
    description = ''
      Automatically share the host's /nix/store with the VM via 9p.

      When enabled, the module injects a share definition:
        { source = "/nix/store"; mountPoint = "/nix/.ro-store";
          tag = "ro-store"; proto = "9p"; }

      This drastically reduces VM disk usage since the VM reuses
      packages already present on the host.
    '';
    type = bool;
    default = true;
  };

  # ── Hypervisor ──
  # Imported from microvm.nix options where possible.

  hypervisor = (imported microvm option).hypervisor;
  # type = enum ["qemu" "cloud-hypervisor" "firecracker"
  #              "crosvm" "kvmtool" "stratovirt" "vfkit"];
  # default = "qemu";

  # ── Resources ──
  vcpu = (imported microvm option).vcpu;
  # type = ints.positive; default = 1;

  mem = (imported microvm option).mem;
  # type = ints.positive; default = 512;

  balloon = (imported microvm option).balloon;
  # type = bool; default = false;

  # ── Networking ──
  interfaces = (imported microvm option).interfaces;
  # type = listOf (submodule { type, id, mac, bridge, macvtap, ... });
  # default = [];

  forwardPorts = (imported microvm option).forwardPorts;
  # type = listOf (submodule { from, proto, host, guest });
  # default = [];

  # ── Storage ──
  volumes = (imported microvm option).volumes;
  # type = listOf (submodule { image, mountPoint, size, fsType, ... });
  # default = [];

  shares = (imported microvm option).shares;
  # type = listOf (submodule { source, mountPoint, tag, proto, ... });
  # default = [];

  storeOnDisk = (imported microvm option).storeOnDisk;
  # type = bool; default = true;

  writableStoreOverlay = (imported microvm option).writableStoreOverlay;
  # type = nullOr str; default = null;

  # ── VSOCK ──
  vsock.cid = (imported microvm option).vsock.cid;
  # type = nullOr ints.positive; default = null;

  # ── Kernel ──
  kernel = (imported microvm option).kernel;
  # type = nullOr package; default = null;

  # ── Hypervisor-specific extras ──
  qemu.extraArgs = (imported microvm option).qemu.extraArgs;
  # type = listOf str; default = [];

  qemu.machine = (imported microvm option).qemu.machine;
  # type = nullOr str; default = null;

  cloud-hypervisor.extraArgs = (imported microvm option).cloud-hypervisor.extraArgs;
  # type = listOf str; default = [];

  # ── Graphics (interactive use only) ──
  graphics.enable = (imported microvm option).graphics.enable;
  # type = bool; default = false;

  # ── Host-side evaluation controls ──
  # These map to microvm.vms.<name> options that control how the VM's
  # NixOS config is evaluated, not the guest content itself.

  pkgs = mkOption {
    description = ''
      Nixpkgs package set to use for evaluating this VM's NixOS config.
      Defaults to the host's package set. Set to null to instantiate a
      fresh package set (useful for cross-system VMs).

      Maps to microvm.vms.<name>.pkgs.
    '';
    type = nullOr unspecified;
    default = null;  # ClusterConfig provides the pkgs from its own context
  };

  nixpkgs = mkOption {
    description = ''
      Path to nixpkgs used for the VM's NixOS evaluation.
      Defaults to the host's nixpkgs path.

      Maps to microvm.vms.<name>.nixpkgs.
    '';
    type = nullOr path;
    default = null;  # ClusterConfig provides nixpkgs
  };

  specialArgs = mkOption {
    description = ''
      Extra arguments passed to the VM's NixOS module evaluation.
      Merged into the specialArgs of the VM's eval-config call.

      Maps to microvm.vms.<name>.specialArgs.
    '';
    type = attrsOf unspecified;
    default = {};
  };

  extraModules = mkOption {
    description = ''
      Additional NixOS modules merged into the VM's config evaluation,
      after the VM's own nixosModules and the microvm guest module.

      Maps to microvm.vms.<name>.extraModules.
    '';
    type = listOf deferredModule;
    default = [];
  };
};
```

#### Options NOT exposed (managed internally)

The following microvm.nix options are intentionally **not exposed** in the ClusterConfig submodule. They are set automatically by the module or are irrelevant in the ClusterConfig context:

| Option | How it's handled |
|---|---|
| `microvm.guest.enable` | Always set to `true` by the module |
| `microvm.optimize.enable` | Always set to `true` by the module |
| `microvm.declaredRunner` | Computed by microvm.nix internally |
| `microvm.runner` | Computed by microvm.nix internally |
| `microvm.hypervisor` | Set from `backend.microvm.hypervisor` |
| `microvm.storeDiskType` | Set by module (squashfs), user can override in nixosModules |
| `microvm.socket` | Derived from VM name automatically |
| `microvm.user` | Not applicable (managed by systemd) |
| `microvm.preStart` | Not applicable |
| `microvm.extraArgsScript` | Not applicable |
| `microvm.cpu` | Rarely needed; user can set in nixosModules |
| `microvm.hugepageMem` | Advanced; user can set in nixosModules |
| `microvm.hotplugMem` | Advanced; user can set in nixosModules |
| `microvm.hotpluggedMem` | Advanced; user can set in nixosModules |
| `microvm.initialBalloonMem` | Advanced; user can set in nixosModules |
| `microvm.deflateOnOOM` | Advanced; user can set in nixosModules |
| `microvm.devices` | Advanced; user can set in nixosModules |
| `microvm.registerWithMachined` | Set by module |
| `microvm.machineId` | Derived from VM name |
| `microvm.kernelParams` | Managed internally |
| `microvm.registerClosure` | Default `true` |
| `microvm.systemSymlink` | Set by module |
| `microvm.prettyProcnames` | Default `true` |
| `microvm.credentialFiles` | Advanced; user can set in nixosModules |
| `microvm.virtiofsd.*` | Tuned by module when virtiofs shares are used |

## 6. Transformation Pipeline Integration

The VM module hooks into the existing transformation pipeline at three stages:

### Stage 1: `clusterTransformations` — Host configuration injection

**What happens**: For every host machine, the module inspects the cluster's VMs and finds which VMs target this host. It then:

1. Adds `microvm.host.enable = true` to the host's `nixosModules` (if any VM targets this host).
2. Adds any additional host-side configuration needed by the backend (e.g. networking setup for tap bridges).

```nix
# Pseudocode:
hostConfigTransformation = config:
  add.nixosModule config (
    clusterName: machineName: machineConfig:
    let
      clusterVms = config.domain.clusters."${clusterName}".vms or {};
      hostedVms = filterAttrs (_: vm: resolveVmHost vm.host == machineName) clusterVms;
    in
    if hostedVms == {} then []
    else [
      { microvm.host.enable = true; }
      # Future: networking auto-setup for tap interfaces, etc.
    ]
  );
```

### Stage 2: `clusterTransformations` — VM NixOS config evaluation and injection

**What happens**: For every VM, the module:

1. Resolves the `host` FQDN to a cluster path.
2. Evaluates the VM's `nixosConfiguration` using `nixpkgs.lib.nixosSystem` with the VM's `nixosModules` plus:
   - The microvm.nix guest module (`microvmNixosModules.microvm`)
   - A module mapping `backend.microvm.*` options to `microvm.*` NixOS options
   - The `shareNixStore` share definition (if enabled)
   - Validation modules that error on disallowed options
3. Injects the evaluated config into the **host machine's** `nixosModules` as `microvm.vms.<vmName>.config`.

```nix
# Pseudocode:
vmInjectionTransformation = config:
  add.nixosModule config (
    clusterName: machineName: machineConfig:
    let
      clusterVms = config.domain.clusters."${clusterName}".vms or {};
      hostedVms = filterAttrs (_: vm: resolveVmHost vm.host == FQDN) clusterVms;

      vmConfigs = mapAttrsToList (vmName: vm:
        let
          backendConfig = mapBackendToMicrovmConfig vm.backend.microvm;
          shareConfig = if vm.backend.microvm.shareNixStore
            then { shares = [{ source = "/nix/store"; mountPoint = "/nix/.ro-store"; tag = "ro-store"; proto = "9p"; }]; }
            else {};

          vmNixosConfig = nixosSystem {
            system = vm.system;
            modules = vm.nixosModules ++ [
              microvmFlakeInput.nixosModules.microvm
              { microvm = backendConfig // shareConfig // forcedOptions; }
              validationModule  # errors on disallowed option overrides
            ];
          };
        in {
          microvm.vms.${vmName} = {
            config = vmNixosConfig.config;
            # runner will be: vmNixosConfig.config.microvm.declaredRunner
          };
        }
      ) hostedVms;
    in
    [ (mkMerge vmConfigs) ]
  );
```

### Stage 3: `deploymentTransformations` — VM build packages

Generate per-VM build scripts for verification:

```nix
# Available as: nix build .#<clusterName>.<vmName>.build
clusterMachine.packages.build = { clusterConfig }:
  let
    this = clusterConfig.clusters.this.vms.this;
    vmName = this.name;
  in
  pkgs.writeShellScriptBin "build-${vmName}" ''
    nix build .#${vmName}.vmConfig --no-link
    echo "VM '${vmName}' configuration builds successfully."
  '';
```

## 7. Host FQDN Resolution

The `host` field accepts FQDNs and resolves them to a `{ cluster, machine }` pair by **searching** the cluster config for a match:

```nix
resolveVmHost = hostFqdn: config:
  let
    suffix = config.domain.suffix;  # e.g. "com"
    # Strip the domain suffix if present
    withoutSuffix =
      let
        suffixLen = builtins.length (lib.splitString "." suffix);
        parts = lib.splitString "." hostFqdn;
        trailing = lib.concatStringsSep "."
          (lib.drop (builtins.length parts - suffixLen) parts);
      in
      if trailing == suffix
      then lib.concatStringsSep "."
        (lib.take (builtins.length parts - suffixLen) parts)
      else hostFqdn;  # assume suffix is already not included

    parts = lib.splitString "." withoutSuffix;
    n = builtins.length parts;

    # Try all split points from left to right:
    #   split at i means: machine = parts[0..i-1], cluster = parts[i..n-1]
    candidates = lib.imap0 (i: _:
      let
        machine = lib.concatStringsSep "." (lib.take (i + 1) parts);
        cluster = lib.concatStringsSep "." (lib.drop (i + 1) parts);
      in
      if config.domain.clusters ? "${cluster}"
         && config.domain.clusters."${cluster}".machines ? "${machine}"
      then { inherit cluster machine; valid = true; }
      else { valid = false; }
    ) parts;

    matches = builtins.filter (c: c.valid) candidates;
  in
  if matches == [] then
    throw ''
      Error: VM references host '${hostFqdn}' but no matching
      <machine>.<cluster> pair was found in the cluster config.
      Available clusters: ${toString (builtins.attrNames config.domain.clusters)}
    ''
  else
    (builtins.head matches);
```

This algorithm walks through all possible split points (giving more parts to the machine name first, since machines are more likely to contain dots than clusters). The first valid `config.domain.clusters.<cluster>.machines.<machine>` wins.

Examples:
| Input `host` | Domain suffix `.com` | Resolved pair |
|---|---|---|
| `host1.example.com` | `.com` | machine=`host1`, cluster=`example` |
| `host1.example` | `.com` | machine=`host1`, cluster=`example` |
| `myhost.prod.kubernetes.example.com` | `.com` | machine=`myhost`, cluster=`prod.kubernetes` |
| `app.db.prod.us-east.example` | `.com` | machine=`app.db`, cluster=`prod.us-east` |

If no match is found:
```
Error: VM references host 'nonexistent.example.com' but no matching
<machine>.<cluster> pair was found in the cluster config.
Available clusters: example, staging
```

## 8. Filter Extensions for VMs

New filter functions in `src/filters.nix`:

```nix
# Select all VMs in a cluster
clusterVms = clusterName: config: [
  "domain.clusters.${clusterName}.vms"
];

# Select a specific VM by name
vmName = vmName: clusterName: config: [
  "domain.clusters.${clusterName}.vms.${vmName}"
];
```

The existing `resolveMachineName` needs a parallel `resolveVmName` (or the function signature needs to handle both paths). Service selectors and roles use filters, so the filter path to VM elements must work identically to machine paths.

## 9. clusterConfig Representation Extension

The `eval.clusterConfig` function in `src/lib.nix` must be extended so the cluster config representation includes VMs alongside machines:

```nix
clusterConfigBase = {
  suffix = config.domain.suffix;
  clusters = forEachAttrIn config.domain.clusters (clusterName: clusterDefinition: rec {
    # ... existing cluster fields ...

    machines = ...;  # existing

    vms = forEachAttrIn clusterDefinition.vms (vmName: vmDefinition:
      attrsets.recursiveUpdate {
        name = vmName;
        fqdn = "${vmName}.${clusterName}.${config.domain.suffix}";
        ips = get.ips vmDefinition.nixosConfiguration.config;
        config = vmDefinition.nixosConfiguration.config;
        host = vmDefinition.host;
        backend = vmDefinition.backend;
        services = lib.attrNames vmDefinition.services;
      }
      (builtins.removeAttrs vmDefinition [
        "nixosConfiguration" "nixosModules" "services" "users"
      ])
    );
  });
};
```

This ensures `clusterConfig.clusters.this.vms.this` works in VM contexts, just like `clusterConfig.clusters.this.machines.this` works in machine contexts.

## 10. User-Facing API Example

```nix
clusterConfig = clusterConfigFlake.lib.buildCluster {
  modules = [
    clusterConfigFlake.clusterConfigModules.default
    clusterConfigFlake.clusterConfigModules.microvm-vms   # NEW module
  ];

  domain = {
    suffix = "com";
    clusters.example = {

      # ── Physical host machine ──
      machines.host1 = {
        system = "x86_64-linux";
        nixosModules = [ ./hosts/host1.nix ];
        # NOTE: microvm.host.enable = true is added AUTOMATICALLY
        # because VMs target this host.
        deployment.targetHost = "192.168.1.10";
      };

      # ── VMs ──
      vms.postgres-vm = {
        system = "x86_64-linux";
        host = "host1.example";   # resolves to clusters.example.machines.host1

        # Lifecycle
        autostart = true;
        restartIfChanged = true;

        nixosModules = [
          ./guests/postgres.nix
          {
            # Network config — same pattern as a machine!
            networking.interfaces.eth0 = {
              ipv4.addresses = [{
                address = "10.0.0.10";
                prefixLength = 24;
              }];
            };
            services.postgresql.enable = true;
          }
        ];

        # Per-VM users (adds to cluster-level users)
        users.dbadmin.systemConfig = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
        };

        backend = {
          type = "microvm";
          microvm = {
            hypervisor = "qemu";
            vcpu = 4;
            mem = 8192;

            # shareNixStore = true;  ← default, no need to specify

            interfaces = [{
              type = "tap";
              id = "vm-postgres";
              mac = "02:00:00:00:00:10";
            }];

            volumes = [{
              image = "/var/lib/microvms/postgres-data.img";
              mountPoint = "/var/lib/postgresql";
              size = 20480;
              autoCreate = true;
            }];

            vmHost = {
              specialArgs = { inherit (inputs) someCustomFlake; };
              extraModules = [ someCustomFlake.nixosModules.default ];
            };
          };
        };
      };

      vms.web-vm = {
        system = "x86_64-linux";
        host = "host1.example.com";   # full FQDN also works

        autostart = true;

        nixosModules = [{
          services.nginx.enable = true;
          networking.firewall.allowedTCPPorts = [ 80 ];
        }];

        backend = {
          type = "microvm";
          microvm = {
            hypervisor = "qemu";
            vcpu = 2;
            mem = 2048;
            forwardPorts = [{
              from = "host";
              host.port = 8080;
              guest.port = 80;
            }];
          };
        };
      };

      # ── Cluster service targeting VMs ──
      services.dns = {
        roles.hosts = [
          filters.clusterMachines
          filters.clusterVms     # VMs contribute their IPs to DNS!
        ];
        selectors = [
          filters.clusterMachines
          filters.clusterVms     # VMs get /etc/hosts entries too!
        ];
      };

    };
  };
};
```

## 11. Module Structure

```
src/modules/vms/
├── CONCEPT.md                ← This document
├── clusterModule.nix         ← Top-level cluster module (entry point)
├── options.nix               ← vmType, backendType option definitions
├── lib.nix                   ← resolveVmHost, mapBackendToMicrovmConfig, etc.
├── microvm/
│   ├── backend.nix           ← microvm submodule options (imports from microvm flake)
│   ├── transformation.nix    ← Injects VM config into host; auto host.enable
│   ├── validation.nix        ← NixOS module that errors on disallowed option overrides
│   └── convenience.nix       ← shareNixStore → shares translation
```

## 12. Flake Registration

```nix
# In flake.nix:

inputs.microvm = {
  url = "github:microvm-nix/microvm.nix";
  inputs.nixpkgs.follows = "nixpkgs";
};

clusterConfigModules.microvm-vms = {
  imports = [ "${self}/src/modules/vms/clusterModule.nix" ];
};
```

## 13. Implementation Steps

1. **`options.nix`** — Define `vmType` and `backendType` (without microvm specifics yet).
2. **`lib.nix`** — Implement `resolveVmHost` FQDN resolution.
3. **`microvm/backend.nix`** — Microvm submodule that imports option definitions from the microvm.nix flake.
4. **`microvm/convenience.nix`** — `shareNixStore` translation logic.
5. **`microvm/validation.nix`** — NixOS module that asserts disallowed options are not overridden.
6. **`microvm/transformation.nix`** — Core: evaluate VM config, inject into host, auto host.enable.
7. **`clusterModule.nix`** — Wire everything together, register transformations.
8. **Filter extensions** — Add `clusterVms` and `vmName` to `src/filters.nix`.
9. **`clusterConfig` representation** — Extend `eval.clusterConfig` in `src/lib.nix` to include VM data.
10. **Flake registration** — Add `microvm-vms` module and `microvm` input to `flake.nix`.
11. **Examples** — Add a worked example in `examples/`.

## 14. Open Questions & Future Considerations

### 14.1 Multi-VM host networking
**Out of scope.** The module cannot assume the user's network setup. Bridge, NAT, and interface configuration are the user's responsibility in the host machine's `nixosModules`. The module only passes the VM's interface declarations through to microvm without any host-side network automation.

### 14.2 VM disk image lifecycle
**Out of scope for now.** Machine disks are managed via disko during `create`. VM disks use microvm's `volumes.autoCreate`. A future disko integration for VM disk images could be valuable but adds complexity.

### 14.4 Shared store with writable overlay
The `shareNixStore` provides a read-only store share. For VMs that need to build packages (e.g. dev VMs), `writableStoreOverlay` can be set. A convenience boolean (`shareNixStoreWritable`) could auto-configure both the share and the overlay.

### 14.5 VM state backup
**Out of scope for the module.** Backup strategies should be defined in separate modules or handled externally, not bundled into the VM module itself.

### 14.6 Nixvirt backend
The nixvirt backend would reuse the same `backendType` pattern:
```nix
backend = {
  type = "nixvirt";
  nixvirt = { ... };  # libvirt domain XML config, memory, CPU, etc.
};
```

### 14.7 Systemd-nspawn backend
Containers via `systemd-nspawn` could share most of the VM pattern:
```nix
backend = {
  type = "nspawn";
  nspawn = { ... };  # container-specific config
};
```
The main difference: nspawn containers share the host kernel and don't need a hypervisor. But the cluster-level abstraction (host binding, service targeting, IP discovery) works identically.
