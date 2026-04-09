# Extending ClusterConfig

ClusterConfig can be extended with modules using the NixOS module system. Cluster modules are **not** the same as machine-level NixOS modules, even though both use the same underlying mechanism (`lib.evalModules`). A cluster module operates at the cluster level and can influence the configuration of multiple machines, add deployment scripts, and define new cluster services.

## How to Use a Module

Add a module to the `modules` list when calling `buildCluster`:

```nix
clusterConfig = clusterConfigFlake.lib.buildCluster {
  modules = [
    clusterConfigFlake.clusterConfigModules.default
    ./my-custom-module.nix           # as a path
    { config = { ... }; }            # as an attribute set
    { pkgs, lib, ... }: { ... }      # as a module closure
  ];

  domain = { ... };
};
```

## Module Arguments

Cluster modules receive the following arguments:

| Argument | Description |
| --- | --- |
| `pkgs` | Nixpkgs package set |
| `lib` | Nixpkgs lib |
| `config` | The evaluated cluster config (not a machine config) |
| `clusterlib` | ClusterConfig helper functions (see below) |
| `filters` | Built-in filter functions |
| `flakeInputs` | All flake inputs passed to the ClusterConfig flake |

## Extension Points

All extensions are configured under `config.extensions`. The extension system provides several targets:

### 1. Cluster-Level Extensions (`extensions.cluster`)

Add options, late-evaluated config, and packages at the cluster level.

```nix
{
  config.extensions.cluster = {

    # New options available under domain.clusters.<name>
    options.myOption = lib.mkOption {
      type = lib.types.str;
      default = "hello";
    };

    # Config values set after final machine evaluation
    # Closures receive { clusterConfig } with the evaluated representation
    late.config.myComputedValue = { clusterConfig }:
      builtins.length (lib.attrNames clusterConfig.clusters.this.machines);

    # Packages available as: nix run .#<clusterName>.<packageName>
    packages.myScript = { clusterConfig }:
      pkgs.writeShellScriptBin "my-script" ''
        echo "Cluster has machines: ${toString (lib.attrNames clusterConfig.clusters.this.machines)}"
      '';
  };
}
```

### 2. Machine-Level Extensions (`extensions.clusterMachine`)

Add options, NixOS modules, and packages at the per-machine level.

```nix
{
  config.extensions.clusterMachine = {

    # New options available under domain.clusters.<name>.machines.<name>
    options.myMachineOption = lib.mkOption {
      type = lib.types.str;
      default = "";
    };

    # NixOS modules added to EVERY machine's configuration
    nixosModules = [
      { environment.systemPackages = [ pkgs.vim ]; }
    ];

    # Config values set after final machine evaluation
    late.config.myValue = { clusterConfig }:
      clusterConfig.clusters.this.machines.this.fqdn;

    # Packages available as: nix run .#<clusterName>.<machineName>.<packageName>
    packages.myMachineScript = { clusterConfig }:
      let
        machineName = clusterConfig.clusters.this.machines.this.name;
      in
      pkgs.writeShellScriptBin "info-${machineName}" ''
        echo "Machine: ${machineName}"
      '';
  };
}
```

### 3. Service Definitions (`extensions.clusterServices`)

Register new cluster services. See [Cluster Services](ClusterServices.md) for a detailed guide.

```nix
{
  config.extensions.clusterServices.myService = {
    defaultModule = import ./myServiceModule.nix;
    roles = [ "primary" "secondary" ];
    options = { ... };
    packages = { ... };
    late.config = { ... };
  };
}
```

### 4. Transformations (`extensions.transformations`)

Add custom transformation functions that run at specific stages of the evaluation pipeline. Each transformation is a function `clusterConfig -> clusterConfig` rewriting the cluster config. For scenarios where the previous extension points are insufficient.

```nix
{
  config.extensions.transformations = {

    # Runs before machines are evaluated
    clusterTransformations = [ myClusterTransform ];

    # Runs after initial machine evaluation, before final evaluation
    moduleTransformations = [ myModuleTransform ];

    # Runs after final machine evaluation, for adding deployment artifacts
    deploymentTransformations = [ myDeploymentTransform ];

    # Runs as the final step, for extracting information
    infoTransformations = [ myInfoTransform ];
  };
}
```

## The `clusterConfig` Representation

Many extension closures (packages, late config) receive a `{ clusterConfig }` argument. This is **not** the raw cluster config but a processed representation that includes:

- `clusterConfig.suffix` — the domain suffix
- `clusterConfig.clusters.<name>.name` — cluster name
- `clusterConfig.clusters.<name>.fqdn` — cluster FQDN
- `clusterConfig.clusters.<name>.machines.<name>` — machine info (name, fqdn, ips, config, services, etc.)
- `clusterConfig.clusters.<name>.services.<name>` — service info with resolved selectors and roles
- `clusterConfig.clusters.this` — points to the current cluster (in machine/service contexts)
- `clusterConfig.clusters.this.machines.this` — points to the current machine (in machine contexts)

The `this` pointers are automatically injected when the closure is evaluated for a specific machine or cluster context.

## Helper Library (`clusterlib`)

ClusterConfig provides helper functions through `clusterlib`:

| Function | Description |
| --- | --- |
| `forEachAttrIn attrSet fn` | Maps a function over an attribute set. Like `mapAttrs` but with reversed attributes for better readability |
| `add.nixosModule config fn` | Adds NixOS modules to each machine via a function `clusterName -> machineName -> machineConfig -> modules` |
| `add.nixosConfigurations config` | Evaluates `nixosModules` and adds `nixosConfiguration` to each machine |
| `add.machinePackages config fn` | Adds flake packages to each machine |
| `add.clusterPackage config fn` | Adds flake packages at the cluster level |
| `add.servicePackages config serviceName fn` | Adds flake packages for a service |
| `update.machines config fn` | Updates machine attributes via `clusterName -> machineName -> machineConfig -> attrs` |
| `update.clusters config fn` | Updates cluster attributes |
| `update.services config fn` | Updates service attributes |
| `eval.clusterConfig config { clusterName; machineName; }` | Builds the clusterConfig representation with `this` pointers |
| `get.machines config` | Returns all machines across all clusters |
| `get.ips machineNixosConfig` | Extracts static IPs from a NixOS config |
<!-- | `ip.tag`, `ip.openTcp`, `ip.staticIpV4OpenTcp` | Helpers for defining service address entries | -->

## Important Limitations

- Extension options (in `extensions.cluster.options`, `extensions.clusterMachine.options`, etc.) **must have default values**. Options without defaults will cause evaluation errors because the clusterConfig representation accesses all option values during construction. Use `lib.types.nullOr` with a default of `null` if a value is inherently optional.

- Cluster modules operate at the cluster level and are evaluated separately from machine NixOS modules. During cluster module evaluation, individual machine NixOS configurations are not yet available (unless you are in a `late.config` closure or a deployment transformation).

## Example: A Complete Module

Here is a module that adds a `monitoring.enable` option to each machine and generates a script to check the status of all machines:

```nix
# monitoring-module.nix
{ pkgs, lib, ... }:
{
  config.extensions = {

    clusterMachine.options.monitoring.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable monitoring on this machine.";
    };

    cluster.packages.check-status = { clusterConfig }:
      let
        machines = lib.attrValues clusterConfig.clusters.this.machines;
        checks = map (m: ''
          echo "Checking ${m.name} (${m.fqdn})..."
          ssh root@${(builtins.head (builtins.attrValues m.ips))} "echo OK" 2>/dev/null || echo "  FAILED"
        '') machines;
      in
      pkgs.writeShellScriptBin "check-status" (lib.concatStringsSep "\n" checks);
  };
}
```