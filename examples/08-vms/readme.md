# Virtual Machine Example

This example demonstrates how to define **virtual machines (VMs)** alongside regular machines in your cluster configuration.
Two microVMs (`microVm0` and `microVm1`) are defined and hosted on the existing cluster machines `vm0` and `vm1`.

## What You Will Learn

- How to define VMs in the cluster configuration
- How the VM `host` field maps a VM to its host machine
- How to configure the microvm.nix backend (hypervisor, CPU, memory, networking)
- How port forwarding provides SSH access to VMs without dedicated IPs
- How to use volumes and impermanence to persist VM state across reboots
- That VMs are deployed automatically as part of their host's configuration

## Prerequisites

- Three VMs already deployed from [Example 01](../01-simpleCluster/)
- The SSH private key added to your SSH agent:

  ```bash
  ssh-add ../00-exampleConfigs/secrets/sshKey
  ```

## Key Concepts

### VM Backends

VMs use a virtualization backend — currently **microvm.nix** (tested with QEMU). The backend defines:

- **Hypervisor**: `"qemu"`, `"cloud-hypervisor"` or other microvm hypervisors
- **Resources**: vCPU count, memory (MB)
- **Networking**: interface types (`user` for NAT, `tap`, `macvtap`, `bridge`)
- **Port forwarding**: expose guest ports on the host (e.g., SSH on port 2222)
- **Volumes**: persistent disk images attached to the VM
- **Shares**: 9p/virtiofs directories shared from host to guest

### How VMs are hosted

VMs are defined alongside machines under `domain.clusters.<name>.vms`. Each VM has a `host` field that references an existing machine by its FQDN (e.g., `"vm0.example.com"`).

The VM module automatically:

1. **Resolves** the host FQDN to find the hosting machine
2. **Enables** `microvm.host.enable = true` on the host (you never set this yourself)
3. **Evaluates** the VM's NixOS configuration
4. **Injects** it into the host under `microvm.vms.<name>.evaluatedConfig`

The host's systemd then manages the VM's lifecycle — rebuilding the host also updates its VMs.

### VM state persistence with impermanence

MicroVMs reset their root filesystem on every boot by default. To keep state across reboots (SSH host keys, machine IDs), this example uses:

- **Volumes**: a persistent disk image (`microVm0-system-config.img`) attached via `backend.microvm.volumes`
- **Impermanence**: the [impermanence](https://github.com/nix-community/impermanence) NixOS module selectively persists files from the volatile root to the persistent volume

```nix
environment.persistence."/persistence/system" = {
  files = [
    "/etc/ssh/ssh_host_ed25519_key"
    "/etc/ssh/ssh_host_ed25519_key.pub"
    "/etc/ssh/ssh_host_rsa_key"
    "/etc/ssh/ssh_host_rsa_key.pub"
  ];
  directories = [
    "/var/lib/nixos"
  ];
};
```

> **Note:** In a production setup with multiple service ports, SSH key persistence may be less critical — you could always re-connect via the host. Here it simplifies debugging.

## Configuration Highlights

The full configuration is in [`flake.nix`](./flake.nix). Key parts:

```nix
vms = {

  microVm0 = {
    system = "x86_64-linux";
    host = "vm0.example.com";
    autostart = true;
    restartIfChanged = true;

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

      volumes = [
        {
          image = "microVm0-system-config.img";
          size = 256;
          label = "system-config";
        }
      ];
    };
  };

  microVm1 = {
    system = "x86_64-linux";
    host = "vm1.example.com";
    autostart = true;
    restartIfChanged = true;

    backend.microvm = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 4096;

      interfaces = [
        { type = "user"; id = "qemu"; mac = "02:00:00:00:00:11"; }
      ];

      forwardPorts = [
        { from = "host"; host.port = 2222; guest.port = 22; }
      ];

      shareNixStore = true;

      volumes = [
        {
          image = "microVm1-system-config.img";
          size = 256;
          label = "system-config";
        }
      ];
    };
  };
};
```

Each VM's `nixosModules` configures:
- **OpenSSH server** with root login for debugging
- **Impermanence** module with persistence for SSH host keys
- **Filesystem** mounting the persistent volume at `/persistence/system`
- **Firewall** allowing SSH on port 22

## Result

Two microVMs are hosted on existing cluster machines:

```
Cluster "example"
├── Machines
│   ├── vm0  (192.168.122.200)  ← hosts microVm0
│   ├── vm1  (192.168.122.201)  ← hosts microVm1
│   └── vm2  (192.168.122.202)
└── VMs
    ├── microVm0  → hosted on vm0, SSH via vm0:2222
    └── microVm1  → hosted on vm1, SSH via vm1:2222
```

## Deployment

Since the machines are already installed (from Example 01), use **colmena** to push the updated configuration that includes the VM definitions:

```bash
nix run .#colmena apply
```

This deploys all machines from all clusters in the flake. Without additional flags, it deploys everything.

Alternatively, deploy target machines individually:

```bash
nix run .#example.vm0.deploy
nix run .#example.vm1.deploy
nix run .#example.vm2.deploy
```

Or use the helper script: `bash deploy.sh`

> **Important**: VMs are **not** deployed separately. They are part of their host machine's NixOS configuration. When you deploy `vm0`, its hosted VM `microVm0` is included automatically.

## Test

Once deployed, verify the VMs are running on their hosts:

```bash
# SSH into a host, then check its microVMs
ssh -o StrictHostKeyChecking=no root@192.168.122.200
systemctl status microvm@microVm0
```

Connect directly to the VM via port forwarding (from the host machine):

```bash
# SSH into microVm0 through vm0's port 2222
ssh -p 2222 -o StrictHostKeyChecking=no root@localhost
```

Note: To connect from outside the host, you need to open the firewall port (2222) on the host machine (vm0/vm1).

## What's Next

- Read the full [Virtual Machines documentation](../../doc/VirtualMachines.md) for detailed reference
- Explore the [microvm.nix manual](https://microvm-nix.github.io/microvm.nix/) and the inherited [backend options](https://microvm-nix.github.io/microvm.nix/microvm-options.html)
- See how VMs can be targeted by cluster services using `filters.clusterVms` and `filters.vmName` in the [Cluster Services documentation](../../doc/ClusterServices.md)