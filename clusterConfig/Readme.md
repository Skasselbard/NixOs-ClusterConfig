# NixClusterConfig

## What is it

- like Nixos Config but with a configuration scope for multiple machines instead of a single machine
- Can be translated to a list of nixosConfigs and deployed to machines

## Concepts

### Config Hierarchy

- each element in the hierarchy gets a domain name for identification, e.g.
  - short forms:
    - "host2"
    - "service1"
  - longForm:
    - host2.cluster4.com
    - service1.example.com

### Selectors

- identifies a configuration element (down the hierarchy)
- effectively the domain name
- should be resolvable in the config hierarchy to:
  - a set of ips (or single ips)
  - a set of hostNames (or a single hostname)
- exports a function that turns (selector, clusterConfig) -> {ip->[dnsName], dnsName->[ip], dnsName -> [config]}
  - TODO: maybe that function belongs in the cluster level?
- each type of configuration element has its own structure, e.g.:
  - physical machines
  - containers
  - VMs
- TODO: should ther be different selector types that can select for different things?

### Cluster Service

- A service that targets multiple hosts or effects multiple configurations
- Can have multiple roles e.g. primary and secondary hosts
  - roles are defined with selectors (TODO: maybe roles are more complex)
- Have a config field for the service config
- Have a function that can turn (config, role, selector) -> NixOSConfig

### Node Service
TODO: necessary?
- A service that only runs on a single machine

### Cluster Config

- Has the following selectors in the hierarchy
  - domain
    - has a suffix (e.g. com or example.com)
    - contains multiple clusters
    - selector example: com or example.com
    - cluster
      - e.g. k3s, example
      - selector example for suffix 'com': k3s.com or example.com
      - service
        - e.g. vault
        - can contain multiple roles
        - selector example for cluster 'example.com': vault.example.com
        - role:
          - e.g. 'api'
          - can contain multiple selectors
          - selector example for service 'vault.example.com': api.vault.example.com
      - machine
        - e.g. host1
        - can have multiple interfaces and virtual sub hosts
        - selector example for cluster 'example.com': host1.example.com
        - interface
          - e.g. eno1
          - can have multiple ip adresses
          - selector example for machine 'host1.example.com': eno1.host1.example.com
        - virtual host
          - e.g. vm1
          - can have zero or more ip addresses
          - selector example for machine 'host1.example.com': vm1.host1.example.com


- following selectors export a function that can generate a config
  - service
  - machine

- following selectors accept a generated config
  - machine
  - virtualization.type
    - format depends on the virtualization type