# Cluster Services

Cluster services are the core mechanism for distributing NixOS configuration across machines. A service is defined once at the cluster level and automatically applied to every machine that matches its selectors.

## Overview

A cluster service consists of:

- **Selectors** — filters that determine which machines receive the service
- **Roles** — named groups of machines that the service can reference
- **ExtraConfig** — an additional NixOS module merged into the selected machines (no closure, no access to resolved roles/selectors)

## Using a Built-In Service

Built-in services are loaded through cluster config modules. For example, the DNS service:

```nix
clusterConfig = clusterConfigFlake.lib.buildCluster {
  modules = [
    clusterConfigFlake.clusterConfigModules.default
    clusterConfigFlake.clusterConfigModules.simple-dns
  ];

  domain = {
    suffix = "home.lan";
    clusters.lab = {
      services.dns = {
        # Apply the service to all machines in the cluster
        selectors = [ filters.clusterMachines ];
        # The "hosts" role determines which machines are added to /etc/hosts
        roles.hosts = [ filters.clusterMachines ];
      };

      machines = { ... };
    };
  };
};
```

The `simple-dns` module registers a service type called `dns` with a `hosts` role. When you configure it in your cluster, you only need to set the `selectors` and `roles` — the service implementation handles the rest.

## Service Configuration Attributes

### Selectors

A list of [filters](Concepts.md#filters) that resolve to nodes (machines and/or VMs). Every node that matches at least one selector filter will receive the service's NixOS modules (`definition` + `extraConfig`).

```nix
services.myService = {
  selectors = [ filters.clusterMachines ];  # all machines
  # or
  selectors = [ filters.clusterVms ];       # all VMs
  # or
  selectors = [ filters.clusterNodes ];     # all machines AND VMs
  # or
  selectors = [ (filters.machineName "node1") (filters.vmName "guest1") ];  # specific nodes
};
```

### Roles

A set of named filter lists. Roles let the service differentiate between groups of nodes — for example, a primary node vs. replicas.

```nix
services.myService = {
  selectors = [ filters.clusterNodes ];
  roles = {
    primary = [ (filters.machineName "node1") ];
    replicas = [ filters.clusterVms ];     # VMs as replicas
  };
};
```

A service definition can alter the generated config for each machine based on its role, e.g. the configuration for the `primary` machine can be different from the `replicas` machines.

### ExtraConfig

An additional NixOS module that is merged into every selected machine. Useful for simple configuration and customization:

```nix
services.myService = {
  selectors = [ filters.clusterMachines ];
  extraConfig = {
    environment.systemPackages = [ pkgs.htop ];
  };
};
```

## How Services Are Evaluated

During the ClusterConfig evaluation pipeline, services go through these steps:

1. **Filter resolution** — The selector filters are evaluated to determine which nodes are targeted. Nodes (machines and/or VMs) matching any selector receive the service.
   Nodes that are not selected are not altered by this service.

2. **Role resolution** — Each role's filters are resolved to node names. The resolved nodes (with their names, IPs, FQDNs, etc.) become available to the node configuration.

3. **Module injection** — For each selected node, the service's `definition` and `extraConfig` are added to the node's NixOS modules. When the node's NixOS configuration is rebuilt, these modules are included.

4. **clusterConfig access** — Inside the service's NixOS module, the node can access `config.clusterConfig` to read resolved service information, including which nodes have which roles.

## Writing a Custom Service Module

A custom cluster service is defined as a cluster config module. It registers a new service type under `config.extensions.clusterServices`.

### Example: A Simple Monitoring Service

```nix
# myMonitoringService.nix
{ lib, ... }:
let
  mkOption = lib.mkOption;
  str = lib.types.str;
  port = lib.types.port;
in
{
  config.extensions.clusterServices.monitoring = {

    # The NixOS module applied to selected machines
    defaultModule = { config, ... }:
      let
        cfg = config.clusterConfig.clusters.this.services.monitoring;
        servers = cfg.roles.server;
      in {
        services.prometheus.exporters.node = {
          enable = true;
          listenAddress = "0.0.0.0";
          bind.port = cfg.metricsPort;
        };
        # Point to the first monitoring server
        services.myAgent.serverAddress =
          (builtins.head servers).fqdn;
      };

    # Declare the roles this service supports
    roles = [ "server" ];

    # Custom options for the service (available at the cluster config level)
    options.metricsPort = mkOption {
      type = port;
      default = 9090;
    };
  };
}
```

Use it in your cluster:

```nix
modules = [ ./myMonitoringService.nix ];

domain.clusters.lab.services.monitoring = {
  selectors = [ filters.clusterMachines ];
  roles.server = [ (filters.hostname "monitor") ];
  metricsPort = 9100;
};
```

### Service Module Structure

A cluster service module sets these attributes under `config.extensions.clusterServices.<serviceName>`:

| Attribute | Type | Description |
| --- | --- | --- |
| `defaultModule` | NixOS module | The NixOS module applied to selected machines |
| `roles` | `listOf str` | List of role names the service supports |
| `options` | `attrsOf anything` | Additional options available in the cluster config |
| `packages` | `attrsOf scriptType` | Scripts added to flake packages (closures receiving `{ clusterConfig }`) |
| `late.config` | `attrsOf scriptType` | Config values set after final machine evaluation |

### Accessing Cluster Info in Service Modules

Inside a service's NixOS module (the `defaultModule`), you have access to `config.clusterConfig`:

```nix
{ config, ... }:
let
  # The current cluster
  cluster = config.clusterConfig.clusters.this;

  # The current node (works for machines AND VMs)
  thisNode = cluster.nodes.this;

  # Machine-specific (only in machine context)
  # thisMachine = cluster.machines.this;

  # VM-specific (only in VM context)
  # thisVm = cluster.vms.this;

  # The current service's config
  serviceConfig = cluster.services.myService;

  # Nodes in the "primary" role — could be machines, VMs, or both
  primaries = serviceConfig.roles.primary;

  # Each node in a role has: .name, .fqdn, .ips, .config, ...
  primaryIp = (builtins.head primaries).ips;
in
{
  # ... NixOS configuration using cluster information
}
```

Note the use of `cluster.nodes.this` instead of `cluster.machines.this` when you want your service to work for both machines and VMs. If your service only applies to machines, use `machines.this` instead.

## Patterns for Writing Services

### Determine Roles

Think about the distinct groups of machines your service needs:
- Does one machine act as a server and others as clients? → `server` and `client` roles
- Is there a leader and followers? → `leader` and `follower` roles
- Does every machine have the same role? → A single role or just use selectors

### Validate Roles

If a role is required (e.g., there must be exactly one primary), add assertions:

```nix
defaultModule = { config, lib, ... }:
  let
    cfg = config.clusterConfig.clusters.this.services.myService;
  in {
    assertions = [{
      assertion = builtins.length cfg.roles.primary == 1;
      message = "myService requires exactly one machine in the 'primary' role";
    }];
    # ...
  };
```

### Generate Host-Dependent Config

When the service needs information that varies per machine (like network interface names), use the `config.clusterConfig.clusters.this.machines.this` attribute to access the current machine's configuration.

## Built-In Services

| Service | Module | Roles | Description |
| --- | --- | --- | --- |
| `dns` | `simple-dns` | `hosts` | Adds static IPs from role machines to `/etc/hosts` on all selected machines |
| `secrets` | `secret-service` | — | Deploys encrypted secrets to machines, decrypted at runtime by a systemd service |
| `kubernetes` | `kubernetes` | (various) | Kubernetes control plane as systemd units (experimental) |
| `vault` | `vault` | (various) | HashiCorp Vault cluster setup and initialization (experimental) |