# Cluster Services

A Cluster Service is a closure that returns a NixOs Module.

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
- The machine config can also be accessed with the `config` attribute set of the resulting NixOs module as with all other modules
  - the config attribute set depends on the currently evaluated machine
  - meaning it is different for each machine even though it is defined in the same service

## Patterns for writing a Service

### Determine Service Roles

- determine all distinct host sets that can be configured
- assign each set a role
  - e.g. if a machine is a default endpoint in the cluster and its configuration differs from other nodes -> expect this as a server role
- assert the role is set as expected if the role is required e.g:
  - at least one entry in the list
  - exactly one entry in the list
- document the role and where it is used

### Host dependent Config

- e.g.: a subset of network interface names from the given host
- should be avoided in general if it cannot be parsed from a generic NixOs machine configuration and needs extra cluster level configuration
---
- define an expected annotation
- if possible set default values
- document the annotation
- read the ``annotations`` attribute set of the ``this`` attribute set given in the service closure for custom configurations
  - if no default value exists for the configuration assert it is set
  - prefer the annotation over the default value