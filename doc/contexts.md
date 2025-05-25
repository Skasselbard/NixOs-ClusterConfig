# Cluster Configuration Contexts

When managing and deploying Cluster Config clusters, it’s essential to distinguish between three distinct **contexts**, each with its own purpose, constraints, and scope:

### 1. **Build Context** — *Declarative Definition of the Cluster*

This context represents the **declarative specification** of the cluster and its machines using Nix. It is concerned with:

* The desired **topology** and **roles** of machines.
* The full **NixOS configuration** for each machine.
* The inputs required to **build** a machine configuration (derivations), such as:

  * `nixosSystem` definitions
  * declarative service settings
  * configuration modules

It defines **what should be built**, but not how or when it is deployed.

**Output**: A set of derivations that can be used for deployment or inspection.

---

### 2. **Machine Context** — *State and Capabilities of a Running Machine*

This context describes the **runtime environment** of an already deployed machine. It includes:

* Files, services, and programs **as they exist on disk and in memory**.
* Paths **on the machine’s filesystem**, not in the Nix store.
* User data and dynamically created resources (e.g., secrets, runtime configs).
* Permissions, sockets, local mounts, or ephemeral state.

**Key distinction**: Unlike the Build Context, this context is concerned with what **is**, not what **should be**.

---

### 3. **Scripting Context** — *Automation and Interaction Layer*

The scripting context is the **imperative layer** responsible for:

* **Deploying** configurations built in the Build Context.
* **Orchestrating** setup steps across machines.
* **Interacting** with the live cluster or querying the cluster definition.

This context operates **outside the target cluster** — typically from a CI/CD system or a management workstation. It has access to both the Build Context (as input) and the Machine Context (via SSH or APIs), allowing it to bridge the declarative and operational worlds.

**Examples**:

* Generating secrets from a user name defined in the Build Context.
* Copying artifacts to specific paths on remote machines.
* Validating whether the deployed state matches the intended configuration.

---

## Context Boundaries and Conflicts

Understanding the boundaries helps avoid common errors or misassumptions. Some examples:

* **Build Context vs. Machine Context**:

  * A file path declared in Nix (e.g., a secret) will be copied into the **Nix store**, making it world-readable unless explicitly protected.
  * Runtime paths (e.g., `/var/lib/secrets/...`) must **not** be defined in the Nix build directly if they are to be dynamically provisioned or encrypted.

* **Machine Context vs. Scripting Context**:

  * A service user may need to exist **both** in the Build Context (for creation) and in the scripting logic (for assigning file ownership).
  * Scripts must often reproduce logic derived from the configuration to perform machine-local actions (e.g., secret generation or rotation).

---

## Summary

| Context               | Purpose                                    | Scope                         | Resides In          |
| --------------------- | ------------------------------------------ | ----------------------------- | ------------------- |
| **Build Context**     | Declarative definition of cluster/machines | Nix expressions / derivations | Nix build system    |
| **Machine Context**   | Actual state and filesystem of machines    | Live machines                 | Cluster nodes       |
| **Scripting Context** | Coordination, deployment, inspection       | Scripts interacting with both | Outside the cluster |

---

## Context Targets of Cluster Modules and Services

Cluster modules and services may operate across multiple contexts.
To use the features of modules and services, it can be important to understand which part of them touches what context.

### Examples:

* **Cluster Modules can target the Scripting Context**  
  Cluster modules can define imperative scripts or actions that interact with the cluster from the outside. For example:

  * Scripts to deploy secrets to machines.
  * Tools to query cluster state or generate derived configuration files.
  * Automation for provisioning infrastructure or orchestrating rollouts.

* **Cluster Modules can target the Build Context**  
  Cluster modules can define declarative aspects of the system. For example:

  * Adding configuration for `home-manager` derivations.
  * Creating annotations that can later be used in scripting or deployment.

* **Cluster Services bridging Contexts**  
  Services usually operate in multiple contexts, with their definitions declared in the **Build Context**, while the service will run in the **Machine Context**.
  Additionally, the **Scripting Context** may also be touched.

  * A cluster service may include a script that deploys encrypted secrets to a machine (scripting context).
  * The same service may also declare a systemd unit on the machine that decrypts those secrets at runtime (machine context).
  * The configuration for both behaviors is described declaratively in the Build Context.
