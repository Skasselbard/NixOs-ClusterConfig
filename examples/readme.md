# Examples

This folder contains progressively more complex example configurations. Each example builds on concepts from previous ones.

Common configurations (NixOS machine configs, SSH keys, password hashes) are shared in the [Common Configuration Folder](./00-exampleConfigs/). Since these examples are designed to be reproducible, the secrets are openly readable. **If you adapt these for real use, restrict access to your [secrets](./00-exampleConfigs/secrets/).**

## Example Overview

| Example | Topic | What You Learn |
| --- | --- | --- |
| [00](./00-exampleConfigs/) | Shared Configuration | Common machine configs, user secrets, and Home Manager modules used by all examples |
| [01](./01-simpleCluster/) | Simple Cluster | Flake structure, machines/users/services, ISO creation, and the `create` deployment workflow |
| [02](./02-formatScripts/) | Format Scripts | The three `formatScript` modes: `null` (skip), `"disko"` (automatic), and custom scripts |
| [03](./03-homeManager/) | Home Manager | Per-user Home Manager modules, the `stateVersion` requirement, and `colmena` updates |
| [04](./04-secretDeployment/) | Secret Deployment (experimental)| Encrypted file secrets with the `secret-service` module, per-user permissions, and the `deploySecrets` command |
| [08](./08-vms/) | Virtual Machines | Defining microVMs alongside machines, the microvm.nix backend, port forwarding, and VM state persistence with impermanence |

> **Note:** Examples 05–07 (Vault, Kubernetes) use older configurations and have not been re-tested with the current version of ClusterConfig.

## Prerequisites

All examples expect:

- A Linux system with Nix installed ([flakes enabled](https://wiki.nixos.org/wiki/Flakes))
- Three virtual machines (see individual example READMEs for network setup details)
  - Each VM uses a **single network interface** with a static IP
  - Internet access for the VMs is provided via **NAT on the host** — see [Example 01](./01-simpleCluster/#host-nat) for details on configuring this on NixOS
- The SSH private key from [secrets/sshKey](./00-exampleConfigs/secrets/sshKey) added to your SSH agent:

  ```bash
  ssh-add ./00-exampleConfigs/secrets/sshKey
  ```

## Getting Started

Start with [Example 01](./01-simpleCluster/) and work through the examples in order. Each example's README explains:

- **What you will learn** — the concepts covered
- **Prerequisites** — what you need before starting
- **Configuration details** — key points about the flake.nix
- **Deployment steps** — exact commands to run
- **Test instructions** — how to verify everything works