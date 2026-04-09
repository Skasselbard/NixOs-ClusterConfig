# NixOs-ClusterConfig

A flake-based framework for declaratively configuring and deploying clusters of NixOS machines.

NixOs-ClusterConfig lets you define the configuration for **multiple NixOS machines** in a single place — a cluster configuration — instead of managing each machine individually.
It extends the familiar NixOS module system to the cluster level: options declared at the cluster scope can influence all machines in the cluster, and services can be defined once and distributed to the machines that need them.

The cluster configuration is evaluated through a multi-stage pipeline and produces:
- A **NixOS system configuration** for each machine
- **Flake packages** with scripts for building, deploying, connecting, and managing the machines

## Key Features

- **Cluster-wide machine configuration** — define services, and users once and have them applied to all (or selected) machines
- **Cluster services** — NixOS modules that are distributed to machines based on filter expressions, with role-based configuration
- **Automated deployment scripts** — generated `nix build` and `nix run` commands for ISO creation, initial setup with [nixos-anywhere](https://github.com/nix-community/nixos-anywhere), and updates with [colmena](https://github.com/zhaofengli/colmena) or `nixos-rebuild`
- **Extensible with modules** — add new cluster-level services, and deployment scripts using the NixOS module system

## Other Modules and Features
- **Kubernetes Integration** — Spin up a highly available Kubernetes cluster based on the ClusterConfig NixOs configurations
- **Home Manager integration** — per-user Home Manager modules can be attached at the cluster level
- **Secret deployment** — encrypted-at-rest secrets that avoid the world-readable Nix store
- **Disk formatting** — [disko](https://github.com/nix-community/disko) integration for declarative partitioning during initial setup

## Scope

NixOs-ClusterConfig is targeted at **home cloud** and small-to-medium infrastructure setups where you manage a handful of physical or virtual NixOS machines.
Larger deployments are still possible but massive scaling is not considered in the design.

## Documentation

| Document | Description |
| --- | --- |
| [Getting Started](doc/GettingStarted.md) | Prerequisites, first cluster setup, and deployment workflow |
| [Concepts](doc/Concepts.md) | Core concepts: domain hierarchy, filters, services, and the evaluation pipeline |
| [Cluster Services](doc/ClusterServices.md) | How to use and write cluster services |
| [Extending ClusterConfig](doc/Extensions.md) | How to write cluster modules and extend the configuration |
| [Contexts](doc/Contexts.md) | Build, Machine, and Scripting contexts explained |
| [Command Reference](doc/CommandReference.md) | All generated `nix build` and `nix run` commands |
| [Examples](examples/readme.md) | Walkthrough examples from a minimal cluster to the different built in cluster services |

## Quick Start

### 1. Create a flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    clusterConfigFlake = {
      url = "github:Skasselbard/NixOs-ClusterConfig";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko/v1.12.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, clusterConfigFlake, ... }:
    let
      system = "x86_64-linux";
      filters = clusterConfigFlake.lib.filters;

      clusterConfig = clusterConfigFlake.lib.buildCluster {
        modules = [
          clusterConfigFlake.clusterConfigModules.default
        ];

        domain = {
          suffix = "example.com";
          clusters.mycluster = {

            users.root.systemConfig = {
              extraGroups = [ "wheel" ];
              hashedPassword = "$6$...";  # your hashed password
              openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
            };

            machines.node1 = {
              inherit system;
              nixosModules = [ ./machines/node1.nix ];
              deployment.targetHost = "192.168.1.10";
            };
          };
        };
      };
    in
    clusterConfig;  # The evaluated cluster config IS the flake output
}
```

### 2. Build and deploy

```bash
# Build an ISO for initial boot
nix build .#mycluster.node1.iso

# Boot the machine from the ISO, then deploy the full system
nix run .#mycluster.node1.create

# For subsequent updates
nix run .#mycluster.node1.deploy

# Or deploy all machines with colmena
nix run .#colmena apply
```

See the [Getting Started guide](doc/GettingStarted.md) and [Examples](examples/readme.md) for detailed walkthroughs.

## Available Modules

The flake provides these cluster config modules under `clusterConfigFlake.clusterConfigModules`:

| Module | Description |
| --- | --- |
| `default` | Bundle of `home-manager`, `nixos-anywhere`, and `colmena` |
| `home-manager` | Adds `homeManagerModules` option to user definitions |
| `nixos-anywhere` | Adds `create` and `format` deployment scripts per machine |
| `colmena` | Generates a colmena hive definition and adds the `colmena` app to the flake |
| `simple-dns` | Populates `/etc/hosts` on selected machines with static IPs from the cluster |
| `secret-service` | Encrypted secret deployment with per-user, per-machine secret definitions |
| `certificates` | TLS certificate generation scripts |
| `kubernetes` | Kubernetes control plane as systemd units (experimental) |
| `vault` | HashiCorp Vault cluster initialization scripts (experimental) |

## Assumptions

- You are running a **Linux system with Nix installed** (with flakes enabled) for building and deploying
- Machines are reachable via **SSH**
- The flake is the central source of configuration
- The data on installation media is disposable and can be overwritten

## License

See [LICENSE](./LICENSE).
