# Virtual Machines (VMs)

NixOs-ClusterConfig lets you define **virtual machines (VMs)** alongside physical machines within a cluster configuration.
VM definitions are a first-class citizen at the cluster level — they participate in the same cluster features (services, users) as machines do.
Currently, only [microvm.nix](https://github.com/astro/microvm.nix) is supported as virtualization backend.

## Overview

In ClusterConfig, a **machine** is an independent NixOS system deployed via SSH (using nixos-anywhere, colmena, or nixos-rebuild).
A **VM** is a guest system that runs *on* a host machine, managed by a hypervisor. Its lifecycle is governed by the host's systemd units (e.g. `microvm@<name>.service`).

Instead of being deployed separately via SSH, a VM's NixOS configuration is **injected into the host machine's configuration**.
The host's hypervisor module (e.g. [microvm.nix](https://github.com/astro/microvm.nix)) builds the VM and creates the systemd service.
Rebuilding and switching the host also updates the VM.

### Machines vs. VMs

| Aspect | Machine | VM |
|---|---|---|
| **Lifecycle** | Independent; deployed via SSH | Managed by host systemd services |
| **Deployment** | nixos-anywhere, colmena, nixos-rebuild | Injected into host's NixOS config |
| **Network** | Physical NIC, own IP on network | Virtual NIC declared in vm backend; IPs configured in `nixosModules` |
| `host` | N/A (self-hosted) | FQDN of the machine that hosts this VM |
| `deployment.targetHost` | Required | N/A |
| `deployment.formatScript` | Optional | N/A |
| **Packages** | `build`, `deploy`, `create`, `iso`, `format`, `connect` | No dedicated VM packages (built as part of host) |

## How It Works

The VM module operates through the ClusterConfig transformation pipeline:

### Stage 1: Host configuration injection

For each VM defined in the cluster, the module resolves its `host` field (an FQDN) to find the hosting machine.
It then adds required configuration to that machine's NixOS modules automatically, e.g. `microvm.host.enable = true` for microvm — you never need to set this manually.

### Stage 2: VM backend config evaluation

The module evaluates the backend configuration for the virtualization backend and adds the resulting config to the host.
This can be options like the amount of vcpus and vm memory and is backend specific.

### Stage 3: VM config injection into host

The evaluated VM configuration is injected into the host machine.

## Configuration Reference

VMs are defined under `domain.clusters.<clusterName>.vms.<vmName>`:

```nix
{
  domain.clusters.example.vms.my-vm = {
    system = "x86_64-linux";
    host = "host1.example.com";   # FQDN of the host machine
    autostart = true;             # Start VM at host boot (default: true)
    restartIfChanged = true;     # Restart VM when host config changes (default: true)

    nixosModules = [
      # Standard NixOS modules for the VM guest
      ({ pkgs, ... }: {
        services.openssh.enable = true;
        networking.firewall.allowedTCPPorts = [ 22 ];
        system.stateVersion = "26.05";
      })
    ];

    backend = {
      type = "microvm";          # Backend discriminator
      microvm = { ... };         # Backend-specific options (see below)
    };
  };
}
```

### VM options

| Option | Type | Default | Description |
|---|---|---|---|
| `system` | `str` | — | NixOS system architecture (e.g. `"x86_64-linux"`) |
| `host` | `str` | — | FQDN of the host machine. Must resolve to an existing machine in the cluster |
| `autostart` | `bool` | `true` | Whether to start this VM automatically at host boot |
| `restartIfChanged` | `bool` | `true` | Whether to restart the VM's systemd service when the host is rebuilt |
| `nixosModules` | list of modules | `[]` | NixOS modules for the VM guest system |
| `users` | (same as machine users) | — | Cluster-level users are applied to VMs automatically; per-VM users supported |
| `backend` | submodule | — | Virtualization backend configuration (see below) |

### Host FQDN resolution

The `host` field accepts either:
- A **full FQDN**: `"host1.example.com"` (with domain suffix)
- A **partial FQDN**: `"host1.example"` (suffix `"com"` is appended automatically)

The resolver strips the domain suffix, then tries all possible split points against `<machine>.<cluster>` pairs.
For example, `"vm0.example.com"` with suffix `"com"` searches for `vm0.example` as a `<machine>.<cluster>` combination:

```text
Parts after stripping suffix: ["vm0", "example"]
Split point 0 → machine: "vm0", cluster: "example"  ← resolved!
```

## Backend: MicroVM (microvm.nix)

The current supported backend is [microvm.nix](https://github.com/astro/microvm.nix), a NixOS module that enables
lightweight virtual machines using QEMU or cloud-hypervisor. Future backends (nixvirt, systemd-nspawn) can be added via the backend abstraction.

VMs created with microvm are always nixos based, so we can treat them largely the same as all other nixos machines in the cluster.

### Backend options

Configured under `backend.microvm`:

```nix
backend = {
  type = "microvm";
  microvm = {
    hypervisor = "qemu";                 # "qemu" or "cloud-hypervisor"
    vcpu = 2;                            # Number of virtual CPUs
    mem = 4096;                          # Memory in MB
    balloon = true;                      # Enable virtio balloon (default: depends on microvm)

    interfaces = [                       # Virtual network interfaces
      {
        type = "user";                   # "user" (NAT), "tap", "macvtap", "bridge"
        id = "qemu";
        mac = "02:00:00:00:00:10";
      }
    ];

    forwardPorts = [                     # Port forwarding (user mode networking)
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];

    volumes = [                          # Persistent disk volumes
      {
        image = "my-vm-system.img";
        size = 256;                      # Size in MB
        label = "system-config";         # Filesystem label (optional)
        # autoCreate = true;             # Automatically create if missing
      }
    ];

    shares = [                           # 9p/virtiofs shares (optional)
      {
        source = "/path/on/host";
        mountPoint = "/path/in/guest";
        tag = "my-share";
        proto = "9p";                    # "9p" or "virtiofs"
      }
    ];

    shareNixStore = true;                # Convenience: adds /nix/store share (see below)

    # Advanced microvm options, check the microvm docu for all of these
    storeOnDisk = false;
    writableStoreOverlay = null;
    vsock.cid = 3;
    kernel = null;                       # Custom kernel package
    qemu.extraArgs = [ "" ];
    qemu.machine = "q35";                # QEMU machine type (advanced)
    cloud-hypervisor.extraArgs = [ "" ];
    graphics.enable = false;

    # Package/module customization
    # WRNING: These options are UNTESTED and my not work as intended in the nixos cluster config
    pkgs = null;                         # Custom pkgs instance for the VM
    nixpkgs = null;                      # Custom nixpkgs for the VM
    specialArgs = { };                   # Probably does not work. Add special args in a separate module instead.
    extraModules = [ ];                  # Do not use this. Use the nixosModules option on the vm level to add nixos modules instead.
  };
};
```

All options listed above are **directly imported from the microvm.nix** flake — they stay in sync with upstream changes.
The full set of microvm options is available (except those listed as managed internally — see below).

#### `shareNixStore` convenience option

`shareNixStore` (`bool`, default: `true`) is a ClusterConfig-specific convenience option that adds a 9p share of the host's `/nix/store`
at `/nix/.ro-store` inside the VM. This allows the VM to reuse the host's store rather than duplicating it.

When enabled (the default), the module automatically appends to `shares`:

```nix
shares = [
  {
    source = "/nix/store";
    mountPoint = "/nix/.ro-store";
    tag = "ro-store";
    proto = "9p";
  }
];
```

Set `shareNixStore = false` if you need to manage `shares` manually or prefer a fully isolated store.

#### Options managed internally

The following microvm options are set automatically by the module and should **not** be set by users:

- `microvm.guest.enable` — Always set to `true` by the module
- `microvm.vms.<name>.evaluatedConfig` — Injected automatically (`config` and `extraModules` are ignored)
- `microvm.host.enable` — Added automatically to host machines

## VM Networking

VMs use the same IP discovery mechanism as machines. The network configuration is split into two parts:

1. **The backend** defines the virtual network interface (type, MAC address, driver):
   ```nix
   backend.microvm.interfaces = [
     { type = "user"; id = "qemu"; mac = "02:00:00:00:00:10"; }
   ];
   ```

2. **The VM's `nixosModules`** configure the network stack for that interface like in every other nixos machine:
   ```nix
   nixosModules = [
     {
       networking.interfaces.eth0.ipv4.addresses = [{
         address = "10.0.2.15";
         prefixLength = 24;
       }];
     }
   ];
   ```

The IPs are extracted from the evaluated VM configuration, making them available to cluster services
(e.g., the `simple-dns` service can add them to `/etc/hosts`).

## Participation in Cluster Features

VMs are fully integrated with the cluster feature set. In fact, ClusterConfig treats machines and VMs as two sub-types of a unified **node** concept — many operations work on `nodes` (both machines and VMs) without distinction.

| Feature | Usage |
|---|---|
| **Service selectors** | `filters.clusterVms`, `filters.vmName` | Target VMs with cluster services (DNS, secrets, etc.) |
| **Service roles** | `roles.myRole = [ filters.vmName "..." ]` | Assign specific VMs to named roles |
| **Cluster users** | `users.admin.systemConfig = { ... }` | Cluster-level users are applied to all VMs automatically |
| **clusterConfig** | `clusterConfig.clusters.this.vms.<name>` | VM info (name, fqdn, ips, config, services) available in modules |

### The `nodes` unified view

ClusterConfig provides three levels of access to cluster participants in the `clusterConfig` representation:

| Attribute | Contains |
|---|---|
| `clusterConfig.clusters.<name>.machines` | Machines only 
| `clusterConfig.clusters.<name>.vms` | VMs only |
| `clusterConfig.clusters.<name>.nodes` | **Both** machines and VMs |

The `nodes` set is a simple merge: `nodes = machines // vms`. This means you can write generic code that works on both machines and VMs without distinction:

```nix
# Inside a node module — works for machines AND VMs
{ config, ... }: {
  let
    node = config.clusterConfig.clusters.this.nodes.this;
  in {
    networking.extraHosts = ''
      ${node.ips.eth0.${0}.address} ${node.fqdn}
    '';
  };
}
```

```nix
clusterConfig.clusters.this.nodes.my-vm.name       # "my-vm"
clusterConfig.clusters.this.nodes.my-vm.fqdn       # "my-vm.example.com"
clusterConfig.clusters.this.nodes.my-vm.ips        # { eth0 = ["10.0.2.15"]; }
clusterConfig.clusters.this.nodes.my-vm.config     # Evaluated NixOS config
clusterConfig.clusters.this.nodes.my-vm.services   # List of assigned services
```

If you need machine-specific fields, use `machines.this`:

```nix
config.clusterConfig.clusters.this.machines.this.deployment.targetHost  # machine only
```

If you need VM-specific fields, use `vms.this`:

```nix
config.clusterConfig.clusters.this.vms.this.host     # VM only
config.clusterConfig.clusters.this.vms.this.backend   # VM only
```

The `this` pointer works across all three views:
- `machines.this` — current machine (only in machine context)
- `vms.this` — current VM (only in VM context)
- `nodes.this` — current node, whether machine or VM (works in both contexts)

### Filter functions

ClusterConfig provides these VM-related filter functions:

| Filter | Usage | Description |
|---|---|---|
| `filters.clusterVms` | `selectors = [ filters.clusterVms ]` | Matches **all** VMs in the cluster |
| `filters.vmName` | `selectors = [ (filters.vmName "my-vm") ]` | Matches a **single** VM by name |
| `filters.clusterNodes` | `selectors = [ filters.clusterNodes ]` | Matches **all machines and VMs** in the cluster |

### Example: Including VMs in the DNS service

```nix
services = {
  dns = {
    roles.hosts = [
      filters.clusterMachines
      filters.clusterVms    # VMs contribute their IPs to DNS
    ];
    selectors = [
      filters.clusterMachines
      filters.clusterVms    # VMs get /etc/hosts entries too
    ];
  };
};
```

## VM Lifecycle

Since VMs are embedded in their host machine's configuration, there is **no separate deployment pipeline** for VMs.
To update a VM:

1. Modify the VM definition (options, `nixosModules`, backend config)
2. Rebuild and deploy the **host machine**: `nix run .#<cluster>.<hostMachine>.deploy`
3. The host's systemd restarts the VM (if `restartIfChanged = true`)

To start/stop a VM manually on the host:

```bash
# Using systemd on the host machine
sudo systemctl start microvm@<vmName>
sudo systemctl stop microvm@<vmName>
sudo systemctl status microvm@<vmName>
```

## Usage Checklist

When adding VMs to your cluster, ensure you have:

- [ ] Loaded the `vms` cluster module (`clusterConfigFlake.clusterConfigModules.vms`)
- [ ] Defined VMs under `domain.clusters.<name>.vms.<name>`
- [ ] Set the `host` field to an FQDN that resolves to an existing machine
- [ ] Configured the `backend` with the desired options
- [ ] Written the VM's NixOS guest configuration in `nixosModules` (for microvm)

The `microvm.host.enable` option is added **automatically** on host machines — do not set it manually.
The `shareNixStore` option defaults to `true`, giving the VM read-only access to the host's Nix store.

## Flake Registration

To use the VM module, load the `vms` module:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    clusterConfigFlake = {
      url = "github:Skasselbard/NixOs-ClusterConfig";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, microvm, clusterConfigFlake, ... }:
    let
      clusterConfig = clusterConfigFlake.lib.buildCluster {
        modules = [
          clusterConfigFlake.clusterConfigModules.default  # includes 'vms'
          # Or, to load only the VM module:
          # clusterConfigFlake.clusterConfigModules.vms
        ];

        domain = {
          suffix = "example.com";
          clusters.mycluster = {
            machines.host1 = {
              system = "x86_64-linux";
              nixosModules = [ ./host1.nix ];
              deployment.targetHost = "192.168.1.10";
            };

            vms.my-vm = {
              system = "x86_64-linux";
              host = "host1.example.com";
              nixosModules = [ ./my-vm.nix ];
              backend.microvm = {
                hypervisor = "qemu";
                vcpu = 2;
                mem = 4096;
                interfaces = [
                  { type = "user"; id = "qemu"; mac = "02:00:00:00:00:10"; }
                ];
                forwardPorts = [
                  { from = "host"; host.port = 2222; guest.port = 22; }
                ];
                shareNixStore = true;
              };
            };
          };
        };
      };
    in
    clusterConfig;
}
```

## VM State Persistence (microvm specific)

MicroVMs reset their root filesystem on every boot by default. For stateful data (SSH host keys, database data, etc.),
you need persistent storage. This is typically done with:

- **Volumes** — persistent disk images attached to the VM (configured via `backend.microvm.volumes`)
- **Impermanence** — the [impermanence](https://github.com/nix-community/impermanence) NixOS module to selectively persist files

Example using both:

```nix
vms.my-vm = {
  system = "x86_64-linux";
  host = "host1.example.com";
  nixosModules = [
    inputs.impermanence.nixosModules.impermanence
    {
      fileSystems."/persist" = {
        device = "/dev/disk/by-label/system-config";
        fsType = "ext4";
        neededForBoot = true;
      };

      environment.persistence."/persist" = {
        files = [
          "/etc/ssh/ssh_host_ed25519_key"
          "/etc/ssh/ssh_host_ed25519_key.pub"
        ];
        directories = [
          "/var/lib/nixos"
        ];
      };

      services.openssh = {
        enable = true;
        settings.PermitRootLogin = "yes";
      };

      system.stateVersion = "26.05";
    }
  ];

  backend.microvm = {
    hypervisor = "qemu";
    vcpu = 2;
    mem = 4096;
    interfaces = [{ type = "user"; id = "qemu"; mac = "02:00:00:00:00:10"; }];
    forwardPorts = [{ from = "host"; host.port = 2222; guest.port = 22; }];
    volumes = [
      {
        image = "my-vm-system.img";
        size = 256;
        label = "system-config";
      }
    ];
  };
};
```

## Backend Abstraction

The VM module uses a type-discriminated backend design, making it straightforward to add new virtualization backends:

```nix
backend = {
  type = "microvm";    # Discriminator — selects which backend to use
  microvm = { ... };   # Backend-specific options (valid when type == "microvm")
  # nixvirt = { ... };  # Future backend
  # nspawn = { ... };   # Future backend
};
```

The backend type determines how the VM options are translated into the host's NixOS configuration.
This design keeps the VM definition interface clean while allowing multiple backends to coexist.

## Questions & Troubleshooting

**Q: My VM doesn't start. How do I debug it?**

Check the host machine's systemd journal:

```bash
journalctl -u microvm@<vmName>.service
```

**Q: Can I SSH into my VM?**

Yes. Configure port forwarding in the backend:

```nix
backend.microvm.forwardPorts = [
  { from = "host"; host.port = 2222; guest.port = 22; }
];
```
And openssh in your modules:

```nix
nixosModules = [{
  services.openssh .enable = true;
}];
```

Then: `ssh -p 2222 <user>@<hostIP>` (include the port in your firewall rules for external access).

For tap/bridge networking, the VM gets its own IP on the network — connect directly.

## Module Structure

```
src/modules/vms/
├── clusterModule.nix       ← Top-level entry point; registers transformations
├── options.nix             ← VM option type definitions (vmType)
└── microvm/
    └── transformation.nix  ← Core logic: evaluates VM configs, injects into hosts
```

The module is registered as `clusterConfigFlake.clusterConfigModules.vms` in the flake.
It is also included in the `default` module bundle.