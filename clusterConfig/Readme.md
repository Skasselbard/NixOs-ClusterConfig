# NixClusterConfig

## What is it

- flake based
- like Nixos Config but with a configuration scope for multiple machines instead of a single machine
- options on the cluster scope can affect multiple machines in the cluster
- Can be translated to a list of nixosConfigs and deployed to machines
- Generates machine specific deployment packages that can be build with nix build or executed with nix run
- Extendable with modules to add configuration features or deployment packages

## Concepts

### Config Hierarchy

- machines are pooled in a cluster
- all clusters are pooled in a root domain
- each machine in the hierarchy can be identified with a domain name  e.g.
  - short forms:
    - "host2"
    - "service1"
  - longForm:
    - host2.cluster4.com
    - service1.example.com
<!-- - other elements can be identified as well ( services and clusters) -->

### Filters

- Filters are functions of the form `clusterName -> clusterConfig -> [clusterPath]`; they take a clusterName and a machineName and resolve them to a list of attribute paths describing clusterConfig elements.
- During clusterConfig evaluation this function is called and `resolved` to the list of elements
- Filters can have more arguments to compute the cluster paths but the last two elements always have to be the cluster name and the clusterConfig, e.g. the hostname filter is a function that takes an additional hostname argument and returns a list with the single element `domain.clusters.${clusterName}.machines.${hostname}`

### Cluster Service

A service is a closure that returns a NixOs Module.

  ```nix
  # Service closure returning a NixOs module attribute
  { selectors, roles, this }:{
    imports = [];
    options = {};
    config = {};
  }
  ```

  ```nix
  # Service closure returning a NixOs module closure
  { selectors, roles, this }:
  {pkgs, lib, ...}:{
    imports = [];
    options = {};
    config = {};
  }
  ```

- Machines configurations can be extended with the NixOs modules returned by the service closures
- Services can target multiple hosts or effects multiple configurations
- Machine that match the `filter` defined by the `selector` of a service will be extended by the service configuration.
---
- Services can have multiple `roles` e.g. primary and secondary hosts
  - roles are a set of named filters
---
- The service closure will be called with the defined `selector` `roles` and a `this` attribute after resolving them to a cluster element.
- As a result you can use the configuration from the resolved elements in the service definition.

#### Service Definition

In the cluster config services are defined in a clusters services attribute with a name and a set of `{selectors, roles, definition, extraConfig }`, e.g.:

```nix
let 
  filters = clusterConfig.lib.filter; # TODO: check flake name is actually "clusterConfig"
in
domain.clusters.example.services = {
  service1 = {
    selectors = [ filters.clusterMachines ];
    roles = { 
      role1 = [ filters.clusterMachines ];
      role2 = [ filters.hostname "host1" ];
    };
    definition = { selectors, roles, this }:{
      service.address = (builtins.head roles.role2.ips);
    };
    extraConfig = {
      service.option = "something";
    };
  };
  service2 = {...};
};
```

##### Selectors

- should be resolvable to a cluster machine in the cluster
- the NixOs module defined by the service `definition` and `extraConfig` will extend the machine that match the selector filters
- the generated `annotations` machine attributes from the selected machines will be used as the `selectors` argument of the service closure in the services `definition` attribute.

##### Roles

- should be resolvable to a cluster element (currently only machines are supported)
- the generated `annotations` machine attributes from the filtered machines from each `role` will be used as the `roles` argument of the service closure in the services `definition` attribute.

##### Definition

- The main configuration closure for the service in the form of `{ selectors, roles, this }:{...}`.
- The closure will be called with the cluster elements (currently only machines) resolved by the filters in the `selectors` and `roles` attributes and a `this` attribute that resolves to the current machine.

##### ExtraConfig

- An additional NixOs module that is copied to the selected machines.
- Here you can put additional service configuration without the need to use closures

#### Service Deployment

Services are copied to all machines that match the filter of the services `selectors` attribute using the following steps:

1. The NixOsConfiguration for all machines in the cluster configuration is built for the first time
2. The `annotations` attribute for machines (and other clusterConfig elements) is generated based on the cluster config and the machines NixOsConfigurations
3. The selector filters are resolved and the entire service is copied to the machines at the resolved cluster config path
4. The roles are resolved to cluster elements
5. The service closure in the `definition` attribute is called with the `annotations` attributes from the resolved selectors, roles and the current machine configuration (in the `this` argument)
6. The NixOsConfigurations are build for a second time
7. The NixOsConfigurations from each machine are [extended](https://nixos.org/manual/nixpkgs/stable/#module-system-lib-evalModules-return-value-extendModules) with
   1. the resulting NixOs module from step 5. and
   2. the NixosModule defined by the services `extraConfig` attribute
   3. for each service added to the (current) machine
