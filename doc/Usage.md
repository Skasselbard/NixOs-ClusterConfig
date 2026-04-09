# Usage

> **Note:** This document is a quick reference. For a detailed walkthrough, see [Getting Started](GettingStarted.md). For all available commands, see the [Command Reference](CommandReference.md).

## Deployment Stages

The deployment process follows three stages:

### Stage 0: Build a Bootable ISO

Build an installation medium for initial machine setup:

```bash
nix build .#<cluster>.<machine>.iso
```

- The ISO inherits network configuration, users, SSH keys, and locale settings from the machine's cluster config
- Write it to a USB drive or mount it in a virtual machine
- The machine booted from the ISO is accessible via SSH

### Stage 1: Initial System Installation

With the target machine booted from the ISO:

```bash
nix run .#<cluster>.<machine>.create
```

This uses [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) to:
1. Optionally run the configured format script (e.g., [disko](https://github.com/nix-community/disko))
2. Install the full NixOS system configuration

After installation, boot from the OS drive.

### Stage 2: Configuration Updates

For ongoing changes, update the deployed system:

```bash
# Single machine
nix run .#<cluster>.<machine>.deploy

# All machines via colmena
nix run .#colmena apply
```

## Working with Secrets

If the `secret-service` module is loaded:

```bash
# Deploy the system first (to update the service itself)
nix run .#<cluster>.<machine>.deploy

# Then deploy secrets
nix run .#<cluster>.<machine>.deploySecrets
```

## Retrieving Hardware Configuration

To fetch the auto-detected hardware configuration from a running machine:

```bash
nix run .#<cluster>.<machine>.hardware-configuration
```

## Connecting to Machines

```bash
nix run .#<cluster>.<machine>.connect
```

Additional SSH arguments can be appended after the command.