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

Filters can be combined in a list — the resulting node set is the union of all matches.

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

### Step 4: Module Transformations

A second round of transformations runs with access to the initial node configurations. In this step:

- The `clusterConfig` representation is generated and injected into each node's NixOS modules
- Service definition modules and extra-config modules are added to the selected nodes' NixOS modules
- Additional NixOS modules from cluster modules are added
- VM configurations are injected into host machine configurations

### Step 5: Final Node Evaluation

NixOS configurations are rebuilt a final time, now including all service modules and the `clusterConfig` representation. This produces the definitive system configuration for each node.

### Step 6: Deployment Transformations

The cluster config is extended with deployment artifacts:

- `nixosConfigurations.<nodeName>` — standard flake attribute for each node
- `packages.<system>.<clusterName>.<nodeName>.*` — build and deployment scripts (ISO, deploy, connect, etc.)
- `packages.<system>.<clusterName>.<serviceName>.*` — service-level scripts
- `colmena` — colmena hive definition (if the colmena module is loaded)
- `apps` — flake apps including the colmena runner

> **Note:** Not all deployment packages work for VMs. VMs do not have `deployment.targetHost`, so scripts like `deploy` and `hardware-configuration` require special handling or gating. VMs are updated by rebuilding and switching their host machine.

### Step 7: Info Transformations

A final pass extracts serializable cluster information and package metadata for inspection and tooling.

## Flake Output Structure

After `buildCluster` completes, the result is a complete flake output. The key attributes:

```text
nixosConfigurations
├── node1       # NixosConfiguration for node1 (machine)
├── node2       # NixosConfiguration for node2 (machine)
└── my-vm       # NixosConfiguration for my-vm (VM)

packages.<system>
└── <clusterName>
    ├── <nodeName>
    │   ├── iso                     # Bootable installation ISO (machines only)
    │   ├── build                   # Local nix build
    │   ├── deploy                  # Remote nixos-rebuild switch (machines only)
    │   ├── connect                 # SSH connection script (machines only)
    │   ├── create                  # nixos-anywhere initial install (machines only)
    │   ├── format                  # Run format script remotely (machines only)
    │   ├── hardware-configuration  # Fetch hardware config (machines only)
    │   └── deploySecrets           # Deploy encrypted secrets (if secret-service is loaded)
    └── <serviceName>
        └── ...                     # Service-specific scripts

colmena                             # Colmena hive definition (if colmena module is loaded)
apps                                # Flake apps (colmena runner, etc.)
```

VMs appear in `nixosConfigurations` (their NixOS config is available) but most deployment scripts (`deploy`, `create`, `iso`, `format`, `hardware-configuration`) are designed for machines and may not work for VMs.