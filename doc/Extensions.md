# Extensions (Rework)

How the cluster config can be extended and implications of the options.

## Extension Basics

The intended way to extend cluster config is to write a cluster config module.
To extend the cluster add your extensions with the ``clusterconfig.extension`` types.
The definition of this types can be found in [extensionOptions.nix](../src/extensionOptions.nix).
Look at the [modules](../src/modules/) and [services](../src/services/) folders for implementations.
Cluster Modules are NOT modules for machine configurations, even though both are [nixOs modules](https://nixos.wiki/wiki/NixOS_modules).
Cluster config reuses nixOs modules to facilitate the module system, however, while the result of a machine configuration is a NixOs System configuration used to setup physical or virtual machines, the Cluster Configs result is essentially a flake that defines several commands, including commands that use machine configurations e.g. to deploy the machine.
Cluster Config modules can define and manipulate machine configuration (NixOs) modules for multiple machines.
During evaluation of Cluster Config machine configurations are known.
During evaluation of machine configurations the Cluster Config is not known.
However, during evaluation of Cluster Config, the machine configuration is extended with information from the cluster.
By convention, Cluster Config information should be added to ``config.clusterCluster`` of each machine configuration managed by the Cluster Config.

## Extension Targets

1. Cluster Service definitions
2. Cluster Machine Definitions
3. Cluster Config Transformations

### Cluster service definitions

Extension option (1): ``clusterconfig.extension.clusterServices``
Defines a new service (2) that can be configured under ``clusterconfig.domain.clusters.{cluster-name}.services``.
The Extension option (1) is used to generate the service options (2).

#### Extension options
##### Default module

Implementation of the service.
A NixOs module for the machine configuration; NOT a module for the cluster config.
Will be copied to all machines that are configured in the service (2) selectors.

Available config:  
All options of the current machine configuration.
Options added by Cluster Config to the machine config under ``config.cluster``.

Unavailable config:
Options set by other services default module (und their imports).

##### Roles
The allowed roles set in the service (2) roles.

##### Scripts
A set of scripts that can be run with the final cluster config generation.
The scripts will be added the flake packages under ``#cluster.{cluster-name}.{service-name}.{script-name}`` and can be run with ``nix run .{script-package}``.
A script definition is a function of the form ``{args} -> derivation``.
The Cluster Config will execute the function add and the resulting derivation to the executable packages.
During Cluster Config evaluation, before executing the function, the ``args`` argument of the function will be populated with the folowing information:

TODO:
- cluster info like in ``config.cluster`` like in the default module?
- other information?
- service config and machine config will be part of it


## Limitations

Extension options (e.g. in ``clusterconfig.extension.clusterServices.options`` or ``clusterconfig.extension.clusterMachine.options``) need a default value, otherwise Cluster Config evaluation will raise the error ``The option `${OptionLocation}' was accessed but has no value defined. Try setting the option.``.
This seems to happen during the build of the Cluster Config representation for the machine configuration.
Building the representation seems to access the values and raise the error.
If you need undefined values, use ``lib.types.nullOr`` in front of your type and set the default value to ``null``;