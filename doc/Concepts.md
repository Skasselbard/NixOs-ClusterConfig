# Core Concepts

This document explains the fundamental concepts behind NixOs-Staged-Hive (ClusterConfig).

## Domain Hierarchy

ClusterConfig organizes machines in a tree-shaped hierarchy:

```text
domain (suffix: "example.com")
└── clusters
    ├── production
    │   ├── machines
    │   │   ├── node1  →  node1.production.example.com
    │   │   └── node2  →  node2.production.example.com
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
- A **machine** is a NixOS system defined within a cluster
- Each machine gets an automatically generated FQDN: `<machineName>.<clusterName>.<suffix>`

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

## Cluster Users

Users can be defined at the cluster level or the machine level:

```nix
clusters.mycluster = {
  # Cluster users — deployed to ALL machines in this cluster
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

A cluster service is a NixOS module that is automatically distributed to machines based on filter expressions. Unlike regular NixOS modules that target a single machine, cluster services can:

- Target multiple machines using **selectors** (filters)
- Adapt their configuration based on **roles** (named sets of machines)
- Access the cluster configuration from within the NixOS module

Services are configured in the cluster definition:

```nix
clusters.mycluster.services = {
  dns = {
    selectors = [ filters.clusterMachines ];  # which machines get this service
    roles.hosts = [ filters.clusterMachines ];  # named groups of machines
    # 'definition' and 'extraConfig' are optional overrides
  };
};
```

The service's NixOS module (its `definition`) receives the resolved cluster information, so it can generate machine-specific configuration from cluster-wide data. For example, the DNS service reads the IPs and hostnames of all machines in the `hosts` role and writes them into each machine's `/etc/hosts`.

For a detailed guide on writing services, see [Cluster Services](ClusterServices.md).

## Filters

Filters are the mechanism that selects which machines a service applies to. A filter is a function with the signature:

```text
clusterName -> clusterConfig -> [ path ]
```

It takes the cluster name and the full cluster config and returns a list of attribute paths pointing to machines in the config (e.g., `"domain.clusters.production.machines.node1"`).

ClusterConfig provides built-in filters via `clusterConfigFlake.lib.filters`:

| Filter | Usage | Description |
| --- | --- | --- |
| `clusterMachines` | `filters.clusterMachines` | Matches **all** machines in the cluster |
| `hostname` | `filters.hostname "node1"` | Matches a **single** machine by name |

Filters can be combined in a list — the resulting machine set is the union of all matches.

### Example

```nix
services.myService = {
  # Apply this service to all machines
  selectors = [ filters.clusterMachines ];

  # Only node1 has the "primary" service role
  roles.primary = [ (filters.hostname "node1") ];

  # All machines have the "replica" service role
  roles.replicas = [ filters.clusterMachines ];
};
```

## The `clusterConfig` in Machine Modules

During evaluation, each machine's NixOS configuration is extended with a `config.clusterConfig` attribute. This gives NixOS modules and service definitions access to the cluster topology:

```nix
# Inside a machine module or service definition
{ config, ... }: {
  # Access the current machine's cluster info
  networking.extraHosts = let
    machines = config.clusterConfig.clusters.this.machines;
  in
    # ... use machines.node1.ips, machines.node1.fqdn, etc.
    "";
}
```

The `clusterConfig` representation includes:

- `clusters.this` — the cluster the current machine belongs to
- `clusters.<name>` — a specific cluster by name
- `clusters.this.machines.this` — the current machine being evaluated
- `clusters.<name>.machines.<name>.name` — machine name
- `clusters.<name>.machines.<name>.fqdn` — fully qualified domain name
- `clusters.<name>.machines.<name>.ips` — static IP addresses grouped by interface
- `clusters.<name>.machines.<name>.config` — the evaluated NixOS configuration
- `clusters.<name>.machines.<name>.services` — list of service names assigned to this machine
- `clusters.<name>.services.<name>` — service info with resolved selectors and roles

Note: the `this` attribute for cluster and machine can be thought of as special `<name>`. However, the `this` machine is only added to the `this` cluster for obvious reasons.

## Evaluation Pipeline

The `buildCluster` function evaluates the cluster configuration through a multi-stage pipeline. Understanding this pipeline helps when writing modules or debugging evaluation issues.

### Step 1: Module Evaluation

The cluster configuration is evaluated using the NixOS module system (`lib.evalModules`). All modules from the `modules` list are included, options are type-checked, and the initial configuration is produced.

### Step 2: Cluster Transformations

A sequence of transformation functions rewrites the cluster config. Each transformation takes a clusterConfig and returns a modified clusterConfig. The default transformations in this step:

- Set `networking.hostName` from the machine attribute name
- Set `networking.domain` from `<clusterName>.<suffix>`
- Set `nixpkgs.hostPlatform` from the machine's `system` attribute
- Copy cluster-level and machine-level users into `users.users.<name>`
- Add Home Manager modules for users (if the home-manager module is loaded)

### Step 3: Initial Machine Evaluation

The NixOS configuration for each machine is built for the first time from its `nixosModules`. After this step, information like IP addresses, FQDNs, and other evaluated config values become available.

### Step 4: Module Transformations

A second round of transformations runs with access to the initial machine configurations. In this step:

- The `clusterConfig` representation is generated and injected into each machine's NixOS modules
- Service definition modules and extra-config modules are added to the selected machines' NixOS modules
- Additional NixOS modules from cluster modules are added

### Step 5: Final Machine Evaluation

NixOS configurations are rebuilt a final time, now including all service modules and the `clusterConfig` representation. This produces the definitive system configuration for each machine.

### Step 6: Deployment Transformations

The cluster config is extended with deployment artifacts:

- `nixosConfigurations.<machineName>` — standard flake attribute for each machine
- `packages.<system>.<clusterName>.<machineName>.*` — build and deployment scripts (ISO, deploy, connect, etc.)
- `packages.<system>.<clusterName>.<serviceName>.*` — service-level scripts
- `colmena` — colmena hive definition (if the colmena module is loaded)
- `apps` — flake apps including the colmena runner

### Step 7: Info Transformations

A final pass extracts serializable cluster information and package metadata for inspection and tooling.

## Flake Output Structure

After `buildCluster` completes, the result is a complete flake output. The key attributes:

```text
nixosConfigurations
├── node1       # NixosConfiguration for node1
└── node2       # NixosConfiguration for node2

packages.<system>
└── <clusterName>
    ├── <machineName>
    │   ├── iso                     # Bootable installation ISO
    │   ├── build                   # Local nix build
    │   ├── deploy                  # Remote nixos-rebuild switch
    │   ├── connect                 # SSH connection script
    │   ├── create                  # nixos-anywhere initial install
    │   ├── format                  # Run format script remotely
    │   ├── hardware-configuration  # Fetch hardware config
    │   └── deploySecrets           # Deploy encrypted secrets (if secret-service is loaded)
    └── <serviceName>
        └── ...                     # Service-specific scripts

colmena                             # Colmena hive definition (if colmena module is loaded)
apps                                # Flake apps (colmena runner, etc.)
```
