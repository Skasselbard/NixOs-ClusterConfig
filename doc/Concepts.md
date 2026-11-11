# Core Concepts

This document explains the fundamental concepts behind NixOs-Staged-Hive (ClusterConfig).

## Domain Hierarchy

ClusterConfig organizes machines in a tree-shaped hierarchy. With the VM module, there are two kinds of **nodes** in a cluster — machines and VMs:

```text
domain (suffix: "example.com")
└── clusters
    ├── production
    │   ├── machines           ← physical / standalone NixOS systems
    │   │   ├── node1  →  node1.production.example.com
    │   │   └── node2  →  node2.production.example.com
    │   ├── vms                ← optional: virtual machines (guests)
    │   │   └── guest1  →  guest1.production.example.com
    │   ├── users (cluster-wide)
    │   └── services
    └── staging
        ├── machines
        │   └── dev1   →  dev1.staging.example.com
        ├── users
        └── services
```

- A **domain** is the root of the configuration, identified by a `suffix` (e.g., `"example.com"`)
- A **cluster** groups machines, users, and services under a name (e.g., `"production"`)
- A **machine** is a NixOS system defined within a cluster — independently deployed via SSH
- A **VM** is a virtual machine (guest) that runs on a host machine — its config is injected into the host
- A **node** is a generic term for any cluster participant — either a machine or a VM
- Each node gets an automatically generated FQDN: `<nodeName>.<clusterName>.<suffix>`

Cluster and node names must contain only letters, digits, underscores or hyphens, start with a letter, digit or underscore, and cannot be `this`. Dots are not allowed. Node names must be unique across machines and VMs within a cluster; short names may repeat in different clusters. Generated `<cluster>-<node>` names must also be unique, since hyphens in either component can produce collisions.

In the flake, this maps to:

```nix
domain = {
  suffix = "example.com";
  clusters = {
    production = {
      users = { ... };
      services = { ... };
      machines = {
        node1 = { ... };
        node2 = { ... };
      };
      vms = {
        guest1 = { ... };
      };
    };
  };
};
```

## Machine Configuration

Each machine definition has these key attributes:

| Attribute | Description |
| --- | --- |
| `system` | The platform, e.g., `"x86_64-linux"` |
| `nixosModules` | A list of NixOS modules that form the machine's system configuration |
| `deployment.targetHost` | The SSH address used for remote deployment |
| `deployment.targetUser` | (Optional) The SSH user for deployment |
| `deployment.formatScript` | (Optional) Format script for initial setup: `null`, `"disko"`, or a custom script |
| `users` | (Optional) Machine-specific users in addition to cluster users |
<!-- | `serviceAddresses` | (Optional) IP/port bindings for services | -->
<!-- | `secrets` | (Optional) Secret definitions (when the secret-service module is loaded) | -->

The `nixosModules` list contains standard NixOS modules — the same kind you would use in a standalone `nixosSystem` call. ClusterConfig adds additional modules during evaluation (e.g., hostname, user definitions, service modules).

## VM Configuration

VMs are defined alongside machines under `domain.clusters.<name>.vms` and share many of the same attributes. See [Virtual Machines](VirtualMachines.md) for a complete reference.

Key differences from machines:
- VMs have a `host` field (FQDN of the machine that runs them) instead of `deployment.targetHost`
- VMs have a `backend` block for virtualization-specific options (hypervisor, vCPU, memory, etc.)
- VMs do **not** have separate deployment scripts — they are built as part of their host machine

## Cluster Users

Users can be defined at the cluster level, or per-node:

```nix
clusters.mycluster = {
  # Cluster users — deployed to ALL nodes (machines + VMs) in this cluster
  users.admin.systemConfig = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "$6$...";
    openssh.authorizedKeys.keys = [ "ssh-ed25519 ..." ];
  };

  machines.node1 = {
    # Machine users — deployed only to this machine
    users.serviceUser.systemConfig = {
      isSystemUser = true;
      group = "serviceUser";
    };
    # ...
  };

  vms.myVm = {
    # Per-VM users — deployed only to this VM
    users.appUser.systemConfig = { ... };
    # ...
  };
};
```

The `systemConfig` attribute is directly mapped to `users.users.<name>` in the NixOS configuration.

When the **home-manager** module is loaded, users also accept a `homeManagerModules` attribute:

```nix
users.admin = {
  homeManagerModules = [
    { home.stateVersion = "24.05"; }
    # ... more home-manager modules
  ];
  systemConfig = { ... };
};
```

## Cluster Services

A cluster service is a NixOS module that is automatically distributed to nodes based on filter expressions. Unlike regular NixOS modules that target a single node, cluster services can:

- Target multiple nodes using **selectors** (filters)
- Adapt their configuration based on **roles** (named sets of nodes)
- Access the cluster configuration from within the NixOS module

Services are configured in the cluster definition:

```nix
clusters.mycluster.services = {
  dns = {
    selectors = [ filters.clusterNodes ];    # which nodes get this service
    roles.hosts = [ filters.clusterNodes ];  # named groups of nodes
    # 'definition' and 'extraConfig' are optional overrides
  };
};
```

The service's NixOS module (its `definition`) receives the resolved cluster information, so it can generate node-specific configuration from cluster-wide data. For example, the DNS service reads the IPs and hostnames of all nodes in the `hosts` role and writes them into each node's `/etc/hosts`.

Services can target machines only, VMs only, or both, by choosing the appropriate filter:

```nix
services = {
  # Target only machines
  dnsForMachines = {
    selectors = [ filters.clusterMachines ];
    roles.hosts = [ filters.clusterMachines ];
  };

  # Target only VMs
  dnsForVMs = {
    selectors = [ filters.clusterVms ];
    roles.hosts = [ filters.clusterVms ];
  };

  # Target all nodes (machines + VMs)
  dnsForAll = {
    selectors = [ filters.clusterNodes ];
    roles.hosts = [ filters.clusterNodes ];
  };
};
```

For a detailed guide on writing services, see [Cluster Services](ClusterServices.md).

## Filters

Filters are the mechanism that selects which nodes a service applies to. A filter is a function with the signature:

```text
clusterName -> clusterConfig -> [ path ]
```

It takes the cluster name and the full cluster config and returns a list of attribute paths pointing to nodes in the config (e.g., `"domain.clusters.production.machines.node1"`).

ClusterConfig provides built-in filters via `clusterConfigFlake.lib.filters`:

| Filter | Usage | Description |
| --- | --- | --- |
| `clusterMachines` | `filters.clusterMachines` | Matches **all machines** in the cluster |
| `clusterVms` | `filters.clusterVms` | Matches **all VMs** in the cluster |
| `clusterNodes` | `filters.clusterNodes` | Matches **all nodes** (machines + VMs) in the cluster |
| `machineName` | `filters.machineName "node1"` | Matches a **single machine** by name |
| `vmName` | `filters.vmName "guest1"` | Matches a **single VM** by name |
| `tagsAny` | `filters.tagsAny "prod"` / `filters.tagsAny [ "prod" "gpu" ]` | Matches **all nodes carrying at least one** of the tags |
| `tagsAll` | `filters.tagsAll "prod"` / `filters.tagsAll [ "prod" "gpu" ]` | Matches **all nodes carrying every** given tag |
| `labelsAny` | `filters.labelsAny { tier = "edge"; zone = "eu-west-1a"; }` | Matches **all nodes where at least one** label pair matches |
| `labelsAll` | `filters.labelsAll { tier = "edge"; zone = "eu-west-1a"; }` | Matches **all nodes where every** label pair matches |
| `hasLabel` | `filters.hasLabel "tier"` | Matches **all nodes declaring** the label key, whatever its value |
| `nodeOption` | `filters.nodeOption [ "deployment" "formatScript" ] "disko"` | Matches **all nodes where the declared node option** at the path equals the value |
| `machineOption` | `filters.machineOption [ "networking" "hostName" ] "web1"` | Matches **all nodes where the evaluated NixOS option** at the path equals the value |

`tagsAny` and `tagsAll` accept a single tag or a list of tags; with a single tag both select the same nodes, so `tagsAll "prod"` is the same as `tagsAny "prod"`. `labelsAny` and `labelsAll` take a set of label values. An empty tag list or an empty label set is rejected instead of silently matching every node.

### Combining Filters

A list of filters is a **union (logical OR)**: a node is selected when at least one filter in the list matches it. This applies to `selectors` and to every role list. Duplicates collapse — a node matched by several filters is returned once, in the order of the first filter that matched it.

```nix
selectors = [
  (filters.tagsAny "prod")          # OR
  (filters.machineName "node1")     # OR
];
```

Use `tagsAll` / `labelsAll` when a node has to match several conditions at once, since a conjunction cannot be expressed by adding filters to the list.

Ordering is not a contract: within one filter the nodes are returned in attribute-name order (machines before VMs), and tag or label lists keep the order of the definition — including across modules, as long as the module merge order is stable.

### Declared and Evaluated Values

`tagsAny`, `tagsAll`, `labelsAny`, `labelsAll`, `hasLabel` and `nodeOption` read the *declared* cluster config, so they work in every pipeline stage, including service `selectors` and `roles`. Both option filters compare Nix values, so query leaf options with plain values (strings, numbers, booleans); functions and derivations cannot be compared.

`machineOption` reads the node's NixOS configuration and therefore needs the initial node evaluation, which happens before selectors are resolved. It is usable in `selectors` and `roles`, but it sees the **initial** configuration: options that service modules or the injected `clusterConfig` set are not part of it yet. It does not evaluate a whole node configuration — only the module-system scaffolding and the queried path — but because every node of the cluster is inspected, it costs a per-node evaluation that `nodeOption` does not. Prefer `nodeOption` when the information is declared in the cluster config.

### Example

```nix
services.myService = {
  # Apply this service to all nodes
  selectors = [ filters.clusterNodes ];

  # Only node1 has the "primary" service role
  roles.primary = [ (filters.machineName "node1") ];

  # All nodes have the "replica" service role
  roles.replicas = [ filters.clusterNodes ];
};
```

## Node Tags and Labels

Every node (machine or VM) accepts two free-form metadata options, `tags` and `labels`:

```nix
clusters.prod.machines.web1 = {
  system = "x86_64-linux";
  tags = [ "prod" "web" "edge" ];
  labels = {
    tier = "edge";
    zone = "eu-west-1a";
  };
  nixosModules = [ /* ... */ ];
};
```

Tags and labels exist because not every classification deserves a typed option. They let a cluster definition describe nodes without a module having to declare the vocabulary first, and they are meaningful for consumers that do not care *which* option encodes a property: selectors, documentation and other tooling.

- `tags` is a set of strings. Tags are merged as a set, so several modules can add tags to the same node and duplicates collapse.
- `labels` is a set of key/value string pairs. Use a label when a consumer looks for a specific key, and a tag when a node is simply part of a group.
- Tags, label keys and label values must match `[A-Za-z0-9]([A-Za-z0-9._-]{0,61}[A-Za-z0-9])?`. Invalid values fail validation before any node is evaluated, so they cannot silently break the consumers of that vocabulary.

Both are available to service definitions under `config.clusterConfig.clusters.<name>.nodes.<node>.tags` and `.labels`, and both can be used for selection with `filters.tagsAny` / `filters.tagsAll` and `filters.labelsAny` / `filters.labelsAll`.

`tags` and `labels` are **not** derived from other options. Facts that already exist as an option — the system, whether a node is a VM, its backend, its host — are queried with `filters.nodeOption` (or `clusterMachines`/`clusterVms`) instead of being duplicated into tags. See [Decisions](Decisions.md) for the reasoning.

## The `clusterConfig` in Machine Modules

During evaluation, each node's NixOS configuration is extended with a `config.clusterConfig` attribute. This gives NixOS modules and service definitions access to the cluster topology:

```nix
# Inside a node module or service definition
{ config, ... }: {
  # Access the current node's cluster info
  networking.extraHosts = let
    nodes = config.clusterConfig.clusters.this.nodes;
  in
    # ... use nodes.node1.ips, nodes.node1.fqdn, etc.
    "";
}
```

The `clusterConfig` representation includes:

### Node-level attributes (per machine or VM)

| Attribute | Description |
| --- | --- |
| `clusters.this` | The cluster the current node belongs to |
| `clusters.<name>` | A specific cluster by name |
| `clusters.this.machines.this` | The current machine being evaluated (machine context only) |
| `clusters.this.vms.this` | The current VM being evaluated (VM context only) |
| `clusters.this.nodes.this` | The current node — works in **both** machine and VM contexts |
| `clusters.<name>.machines.<name>.name` | Machine name |
| `clusters.<name>.machines.<name>.fqdn` | Machine fully qualified domain name |
| `clusters.<name>.machines.<name>.ips` | Machine static IP addresses grouped by interface |
| `clusters.<name>.machines.<name>.config` | Machine evaluated NixOS configuration |
| `clusters.<name>.machines.<name>.services` | List of service names assigned to this machine |
| `clusters.<name>.vms.<name>` | Same structure as machines (name, fqdn, ips, config, services, host, backend) |
| `clusters.<name>.nodes.<name>` | Unified view — contains **both** machines and VMs |
| `clusters.<name>.services.<name>` | Service info with resolved selectors and roles |

The `this` attributes serve as special pointers to the current context. `clusters.this` points to the current cluster, `nodes.this` points to the current node (whether machine or VM), `machines.this` points to the current machine (only available in machine context), and `vms.this` points to the current VM (only available in VM context).

## Evaluation Pipeline

The `buildCluster` function evaluates the cluster configuration through a multi-stage pipeline. Understanding this pipeline helps when writing modules or debugging evaluation issues.

### Step 1: Module Evaluation

The cluster configuration is evaluated using the NixOS module system (`lib.evalModules`). All modules from the `modules` list are included, options are type-checked, and the initial configuration is produced.

### Step 2: Cluster Transformations

A sequence of transformation functions rewrites the cluster config. Each transformation takes a clusterConfig and returns a modified clusterConfig. The default transformations in this step:

- Set `networking.hostName` from the node attribute name
- Set `networking.domain` from `<clusterName>.<suffix>`
- Set `nixpkgs.hostPlatform` from the node's `system` attribute
- Copy cluster-level and node-level users into `users.users.<name>`
- Add Home Manager modules for users (if the home-manager module is loaded)

### Step 3: Initial Node Evaluation

The NixOS configuration for each node (machine and VM) is built for the first time from its `nixosModules`. After this step, information like IP addresses, FQDNs, and other evaluated config values become available.

### Step 4: Selector Validation and Service Selection

The selectors and roles of every service are validated, and each service is copied onto the nodes its selectors resolve to. Selected nodes gain a `services` attribute that holds the service definition with `selectors` and `roles` resolved to node names.

This step runs after the initial node evaluation and is not part of `extensions.transformations`, so that selectors can use `filters.machineOption` — they query the **initial** machine configuration, so options that only service modules or the injected `clusterConfig` set are not visible to a selector. See [Decisions](Decisions.md#d3-selectors-may-query-the-first-pass-machine-configuration).

### Step 5: Module Transformations

A second round of transformations runs with access to the initial node configurations and to the selected services. In this step:

- The `clusterConfig` representation is generated and injected into each node's NixOS modules
- Service definition modules and extra-config modules are added to the selected nodes' NixOS modules
- Additional NixOS modules from cluster modules are added

### Step 6: Final Node Evaluation

NixOS configurations are evaluated again with all service modules and the `clusterConfig` representation. After final guest evaluation, host modules inject the final guest configurations; affected hosts are then evaluated again.

The `clusterConfig` injected into these modules reflects the **initial** NixOS evaluation. In particular, its IP addresses and `node.config` do not include changes introduced by service modules. Package and late-config closures receive a later view. The microVM host transformation runs after final guest evaluation and injects that final guest configuration into the host; affected hosts are evaluated again.

### Step 7: Deployment Transformations

The cluster config is extended with deployment artifacts:

- `nixosConfigurations.<cluster>-<node>` — standard flake attribute for each node. The old unqualified names are no longer provided.
- `packages.<system>.<clusterName>.<nodeName>.*` — build and deployment scripts (ISO, deploy, etc.)
- `packages.<system>.<clusterName>.<serviceName>.*` — service-level scripts
- `colmena` — colmena hive definition (if the colmena module is loaded)
- `apps` — flake apps including the colmena runner

> **Note:** Machine-only deployment packages are not generated for VMs. MicroVM guests are updated by rebuilding and switching their host machine.

### Step 8: Info Transformations

A final pass extracts serializable cluster information and package metadata for inspection and tooling.

## Flake Output Structure

After `buildCluster` completes, the result is a complete flake output. The key attributes:

```text
nixosConfigurations
├── production-node1
├── production-node2
└── production-my-vm

packages.<system>
└── <clusterName>
    ├── <nodeName>
    │   ├── iso                     # Bootable installation ISO (machines only)
    │   ├── build                   # Local nix build
    │   ├── deploy                  # Remote nixos-rebuild switch (machines only)
    │   ├── create                  # nixos-anywhere initial install (machines only)
    │   ├── format                  # Run format script remotely (machines only)
    │   ├── hardware-configuration  # Fetch hardware config (machines only)
    │   └── secretsCheck            # Check secrets (if secret-service is loaded)
    └── <serviceName>
        └── ...                     # Service-specific scripts

colmena                             # Colmena hive definition (if colmena module is loaded)
apps                                # Flake apps (colmena runner, etc.)
```

VMs appear in `nixosConfigurations`, but machine-only deployment scripts are not generated for them.