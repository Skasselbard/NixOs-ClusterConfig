## Nixos Modules and building nixos configurations.

### Involved fields

Host:

- config.domain.cluster.<name>.machines.<name>.nixosConfiguration
- the build host configuration
- set by add.nixosConfiguration
- build form config.domain.cluster.<name>.machines.<name>.nixosModules
- modules most contain a module with the vm config(s)
  - e.g. {microvm.vms.<name> = ...;}
- config.domain.cluster.<name>.machines.<name>.nixosModules
- must contain the modules for the vm definition
- for each vm microvm.vms.<name>.evaluatedConfig must be set
  - needed by microvm to build the vms
  - should be the same as the vm field config.domain.cluster.<name>.vms.<name>.nixosConfiguration
  - should be build from vm field config.domain.cluster.<name>.vms.<name>.nixosModules

MicroVm:

- config.domain.cluster.<name>.vms.<name>.nixosConfiguration
- config.domain.cluster.<name>.vms.<name>.nixosModules

### Workflow

1. add vm modules to config.domain.cluster.<name>.vms.<name>.nixosModules
2. build config.domain.cluster.<name>.vms.<name>.nixosConfiguration
3. add the config from 2. to config.domain.cluster.<name>.machines.<name>.nixosModules inside a module under microvm.vms.<name>.evaluatedConfig
