# Contexts

When working with ClusterConfig, it is important to understand the three distinct contexts in which code and configuration operate. Confusing them can lead to subtle bugs — for example, putting secrets in the Nix store (world-readable) instead of deploying them separately.

## 1. Build Context — Declarative Definition

The build context is everything that happens inside Nix expressions during evaluation and build time. It is concerned with:

- The **desired state** of the cluster: topology, roles, machine configurations
- **NixOS configurations** (derivations) for each machine
- **Cluster services** and their definitions
- **Deployment scripts** that are generated as derivations

**Key property:** Values embedded in derivations or copied as paths can end up in the world-readable **Nix store**. Sensitive data (passwords and private keys) must not be embedded in NixOS modules, scripts or store paths.

**Output:** A set of derivations — system configurations, scripts, ISOs — that can be deployed or inspected.

## 2. Machine Context — Runtime State

The machine context describes the **actual state** of a deployed machine at runtime:

- Files, services, and processes as they exist on disk and in memory
- **Filesystem paths** (not Nix store paths) where runtime data lives
- Dynamically created resources: secrets, certificates, runtime configuration
- User data, permissions, mounts, and ephemeral state

**Key property:** Unlike the build context, this deals with **what is**, not what should be.

**Example:** sops-nix decrypts encrypted files on the target and exposes the plaintext at configured runtime paths; the plaintext is not part of the Nix store.

## 3. Scripting Context — Automation Layer

The scripting context is the **imperative layer** that bridges build and machine contexts:

- **Deploying** configurations built in the build context to machines
- **Orchestrating** multi-step setup across machines
- **Interacting** with live machines via SSH
- **Managing** secrets, certificates, and other sensitive data

This context operates **outside the target cluster** — typically from your workstation or a CI system. It has access to the build context (as input) and the machine context (via SSH).

**Examples:**
- The `nix run .#<cluster>.<machine>.create` command connects to a machine via SSH, runs the format script, and installs NixOS
- The `nix run .#<cluster>.<machine>.secretsInstallKey` command provisions a managed target identity.

## Context Boundaries

Understanding where one context ends and another begins helps avoid common mistakes:

### Build Context vs. Machine Context

| Aspect | Build Context | Machine Context |
| --- | --- | --- |
| Where it runs | Nix evaluator / builder | On the deployed machine |
| Data visibility | World-readable (Nix store) | Controlled by permissions |
| When it runs | During `nix build` / `nix run` | After deployment, at runtime |
| Secrets | ❌ Must not contain secrets | ✅ Secrets live here |

### Machine Context vs. Scripting Context

| Aspect | Machine Context | Scripting Context |
| --- | --- | --- |
| Where it runs | On the deployed machine | On your workstation / CI |
| Access | Local filesystem, systemd, etc. | SSH to machines |
| Purpose | Running services | Deploying, orchestrating |

### Practical Example: Secret Deployment

The secret-service module touches all three contexts:

1. **Build context:** Declares secret locations and includes encrypted sops files in the NixOS closure.
2. **Scripting context:** Helpers manage sops recipients and provision target identities without putting private keys in the store.
3. **Machine context:** sops-nix decrypts secrets on the target and sets their ownership and permissions.

## Context Targets of Modules and Services

When writing or using modules and services, it helps to identify which contexts they touch:

- **Cluster modules** primarily operate in the **build context** (defining options, transformations, NixOS modules) but can also generate scripts for the **scripting context** (via `packages`)
- **Cluster services** typically span all three:
  - Their configuration is declared in the **build context**
  - Their NixOS module runs in the **machine context**
  - Their deployment scripts operate in the **scripting context**

Being explicit about context boundaries in your own modules makes them easier to reason about and avoids security pitfalls like accidentally exposing secrets through the Nix store.
