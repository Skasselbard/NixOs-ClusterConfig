# Simple Cluster Example

Build a minimal functional cluster with three virtual machines, a cluster user, and a static DNS service.

## What You Will Learn

- How to structure a ClusterConfig flake
- How to define machines, users, and services in a cluster
- The three-stage deployment workflow: build ISO → boot → create

## Prerequisites

- A Linux machine with Nix installed ([flakes enabled](https://wiki.nixos.org/wiki/Flakes))
- Three virtual machines you can deploy to
  - Each VM needs one network interface on a virtual network (e.g. the libvirt default NAT network `virbr0`)
  - The interface will be assigned a **static IP** for predictable cluster communication
  - Internet access for the VMs is provided through NAT on the **host machine** — see the [Host NAT](#host-nat) section below
  - The VMs should boot from ISO images
  - You may need to adjust the disk device path in the [machine config](../00-exampleConfigs/machines/vm.nix) to match your hypervisor
- The SSH private key from [secrets/sshKey](../00-exampleConfigs/secrets/sshKey) added to your SSH agent:

  ```bash
  ssh-add ../00-exampleConfigs/secrets/sshKey
  ```

### Host NAT

The example VMs have only one network interface with a static IP. To give them internet access (required for downloading packages during `nixos-anywhere` deployment), the **host machine** must provide NAT / masquerading for the virtual network.

If your host runs **NixOS** and you use libvirt, you may need to add this to your host configuration:

```nix
networking.nat = {
  enable = true;
  externalInterface = "enp0s3";    # Replace with your host's internet-facing interface
  internalInterfaces = [ "virbr0" ]; # The libvirt NAT network bridge
};
```

On other Linux distributions, configure iptables/nftables to masquerade traffic from `192.168.122.0/24` through your internet-facing interface.

> **Tip:** If you are running these VMs on a laptop that changes networks (Wi-Fi / Ethernet), the `externalInterface` may vary. Consider using a routing tool or a dynamic firewall rule that adapts to the active connection.

## Result

Three virtual machines with:

- A fresh NixOS installation on formatted drives
- Static IPs as configured in [00-exampleConfigs/default.nix](../00-exampleConfigs/default.nix):
  - vm0: `192.168.122.200`
  - vm1: `192.168.122.201`
  - vm2: `192.168.122.202`
- A `root` user (password: `root`) with SSH key authorization
- A `/etc/hosts` file on each machine with entries for all three cluster machines (via the DNS service)

## Flake Structure

The `flake.nix` demonstrates the basic ClusterConfig pattern:

```text
inputs:   nixpkgs + clusterConfigFlake + disko
            ↓
outputs:  buildCluster { modules, domain.clusters.example.{services, users, machines} }
            ↓
result:   flake outputs (nixosConfigurations, packages, colmena)
```

Key points:

- **Modules** load framework features (`default` = nixos-anywhere + colmena + home-manager, `simple-dns` = the DNS service)
- **Services** use `selectors` (who gets the module) and `roles` (who provides data)
- **Users** are deployed on all cluster machines
- **Machines** define per-host NixOS config and deployment settings
- The result of `buildCluster` is returned directly as the flake output

## Deployment

### 1. Build ISO images

```bash
nix build .#example.vm0.iso -o ./build/vm0/
nix build .#example.vm1.iso -o ./build/vm1/
nix build .#example.vm2.iso -o ./build/vm2/
```

Or use the helper script: `bash build-isos.sh`

> The package path follows the pattern `.#<cluster>.<machine>.<command>`.

### 2. Boot VMs from the ISO

Start each VM with its ISO mounted as a boot drive. The ISO provides a minimal NixOS environment that accepts SSH connections for deployment.

### 3. Deploy machine configurations

```bash
nix run .#example.vm0.create
nix run .#example.vm1.create
nix run .#example.vm2.create
```

Or use the helper script: `bash deploy.sh`

> `create` uses [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) to format the disk (if `formatScript` is set) and install the full NixOS configuration remotely.

### 4. Reboot

Boot the VMs from their OS drive (remove the ISO). The machines are now running your cluster configuration.

## Test

Verify that the DNS service works — machines should resolve each other by hostname:

```bash
# SSH into vm0 and ping vm1 by name
ssh root@192.168.122.200 "ping -c 1 vm1"
```

Or run all tests: `bash test.sh`

## What's Next

- [Example 02](../02-formatScripts/) — different format script options
- [Example 03](../03-homeManager/) — per-user Home Manager configuration
- [Example 04](../04-secretDeployment/) — deploying encrypted secrets