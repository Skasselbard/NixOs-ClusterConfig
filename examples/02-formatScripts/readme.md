# Format Scripts Example

Control how disks are formatted during initial deployment using the `deployment.formatScript` option.

This example shows the three available modes: skip formatting, automatic disko formatting, and custom format scripts.

## What You Will Learn

- The three `formatScript` modes: `null`, `"disko"`, and custom scripts
- How to extract and wrap disko's generated format script for custom workflows
- When to use each mode

## Prerequisites

- Three virtual machines deployed from [Example 01](../01-simpleCluster/) (or freshly booted from ISOs)
- The SSH private key added to your SSH agent:

  ```bash
  ssh-add ../00-exampleConfigs/secrets/sshKey
  ```

## Format Script Options

| Machine | `formatScript` | Behavior |
| --- | --- | --- |
| vm0 | `null` | Skips formatting entirely. Installs NixOS directly on existing partitions. |
| vm1 | `"disko"` | Auto-generates a format script from the `disko.devices` config and runs it. |
| vm2 | Custom script | Extracts the disko script manually and wraps it with custom pre/post commands. |

### When to use each mode

- **`null`** — The machine is already formatted, or you want to format manually from the boot ISO.
- **`"disko"`** — Standard case: let disko handle everything based on your partition config.
- **Custom script** — You need fine-grained control, e.g., formatting OS drives but preserving data drives, or running pre/post-format commands.

## Deployment

Build ISOs and boot the VMs (reuse from [Example 01](../01-simpleCluster/) or rebuild):

```bash
nix build .#example.vm0.iso -o ./build/vm0/
nix build .#example.vm1.iso -o ./build/vm1/
nix build .#example.vm2.iso -o ./build/vm2/
```

Deploy the machines:

```bash
nix run .#example.vm0.create
nix run .#example.vm1.create
nix run .#example.vm2.create
```

Or use the helper script: `bash deploy.sh`

## Verifying

During deployment, observe the output:

- **vm0**: You should see a message indicating that formatting is skipped
- **vm1**: Disko formats the disk silently (standard output)
- **vm2**: You should see the custom echo messages **before** and **after** the disko formatting step

## What's Next

- [Example 03](../03-homeManager/) — per-user Home Manager configuration
- [Example 04](../04-secretDeployment/) — deploying encrypted secrets
