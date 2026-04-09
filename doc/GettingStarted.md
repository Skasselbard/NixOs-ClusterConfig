# Getting Started

This guide walks you through setting up your first cluster with NixOs-Cluster-Config.

## Prerequisites

- A **Linux system** with [Nix](https://nixos.org/download.html) installed
- **Flakes** enabled in your Nix configuration (add `experimental-features = nix-command flakes` to `/etc/nix/nix.conf` or `~/.config/nix/nix.conf`)
- One or more target machines reachable via **SSH**
- An SSH key pair (the public key will be deployed to the machines)

## Project Structure

A typical ClusterConfig project is a Nix flake. The recommended structure:

```text
my-cluster/
├── flake.nix           # Main entry point
├── flake.lock          # Locked dependencies
├── machines/           # NixOS configurations for individual machines
│   ├── node1.nix
│   └── node2.nix
└── secrets/            # SSH keys, password hashes, etc.
    └── ...
```

## Step 1: Set Up the Flake

Create a `flake.nix` that imports ClusterConfig and your machine configurations:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    clusterConfigFlake = {
      url = "github:Skasselbard/NixOs-ClusterConfig";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Required for disk formatting during initial deployment
    disko = {
      url = "github:nix-community/disko/v1.12.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, clusterConfigFlake, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      filters = clusterConfigFlake.lib.filters;

      clusterConfig = clusterConfigFlake.lib.buildCluster {

        # Load modules for deployment capabilities
        modules = [
          clusterConfigFlake.clusterConfigModules.default  # home-manager + nixos-anywhere + colmena
          clusterConfigFlake.clusterConfigModules.simple-dns  # static DNS via /etc/hosts
        ];

        domain = {
          suffix = "home.lan";

          clusters.lab = {

            # Cluster-wide users — applied to every machine
            users.root.systemConfig = {
              extraGroups = [ "wheel" ];
              hashedPassword = "$6$...";  # generate with: mkpasswd -m sha-512
              openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
            };

            # Optional: cluster services
            services.dns = {
              roles.hosts = [ filters.clusterMachines ];
              selectors = [ filters.clusterMachines ];
            };

            # Machine definitions
            machines = {
              node1 = {
                inherit system;
                nixosModules = [
                  ./machines/node1.nix
                  inputs.disko.nixosModules.default
                ];
                deployment = {
                  targetHost = "192.168.1.10";
                  formatScript = "disko";  # format drives on initial setup
                };
              };

              node2 = {
                inherit system;
                nixosModules = [
                  ./machines/node2.nix
                  inputs.disko.nixosModules.default
                ];
                deployment = {
                  targetHost = "192.168.1.11";
                  formatScript = "disko";
                };
              };
            };
          };
        };
      };
    in
    clusterConfig;  # The result of buildCluster IS the flake output
}
```

> **Important:** The return value of `buildCluster` must be the flake output. It contains `nixosConfigurations`, `packages`, `apps`, and other standard flake attributes.

## Step 2: Write Machine Configurations

Each machine needs a standard NixOS configuration module. This is normal NixOS — no ClusterConfig-specific syntax required:

```nix
# machines/node1.nix
{ pkgs, config, ... }: {
  system.stateVersion = "24.05";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = config.services.openssh.ports;

  # Static IP for predictable connectivity
  networking.interfaces."eth0".ipv4.addresses = [{
    address = "192.168.1.10";
    prefixLength = 24;
  }];

  # Disko partitioning (if using disko)
  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "500M";
          content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; };
        };
        root = {
          size = "100%";
          content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
        };
      };
    };
  };
}
```

## Step 3: Deployment Workflow

ClusterConfig uses a staged deployment approach:

### Stage 0: Build an Installation ISO

Build a bootable ISO image that inherits network configuration, users, and SSH keys from the machine config:

```bash
nix build .#lab.node1.iso
```

Write the ISO to a USB drive or mount it as a virtual CD and boot the target machine from it.

### Stage 1: Initial System Installation

With the machine booted from the ISO and reachable via SSH, deploy the full system configuration:

```bash
nix run .#lab.node1.create
```

This uses [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) to:
1. Run the configured format script (e.g., disko) to partition and format drives
2. Install the complete NixOS system built from the machine's `nixosModules`

After installation, reboot the machine from its OS drive.

### Stage 2: Ongoing Configuration Updates

For subsequent changes, update and deploy with:

```bash
# Deploy a single machine
nix run .#lab.node1.deploy

# Or deploy all machines with colmena
nix run .#colmena apply
```

## Useful Commands

Once your cluster is set up, you have these generated commands available:

```bash
# Build/deploy
nix build .#<cluster>.<machine>.iso       # Build installation ISO
nix run .#<cluster>.<machine>.create      # Initial system install (nixos-anywhere)
nix run .#<cluster>.<machine>.deploy      # Update system config (nixos-rebuild)
nix run .#<cluster>.<machine>.build       # Build system locally without deploying

# Utilities
nix run .#<cluster>.<machine>.connect     # SSH into the machine
nix run .#<cluster>.<machine>.hardware-configuration  # Print hardware config

# Fleet management
nix run .#colmena apply                   # Deploy all machines via colmena
```

See the [Command Reference](CommandReference.md) for a full list.

## Next Steps

- Read the [Concepts](Concepts.md) guide to understand the evaluation pipeline and how services work
- Browse the [Examples](../examples/readme.md) for progressively more complex configurations
- See [Cluster Services](ClusterServices.md) to learn how to write services that span multiple machines
