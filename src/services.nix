{ lib, clusterlib, ... }:
let
  # imports
  asserts = lib.asserts;
  strings = lib.strings;
  attrsets = lib.attrsets;
  lists = lib.lists;

  filters = import ./filters.nix { inherit lib; };

  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;
  update = clusterlib.update;
  filtersToPaths = filters.filtersToPaths;

  # assert filter properties and assemble error message
  filterFormatIsOk =
    filter:
    asserts.assertMsg (strings.hasPrefix "domain" filter) "Filter '${filter}' does not start with 'domain'. Filters need to be a path in the clusterConfig in the form like 'domain.clusterName.machineName'";

  # Copies all services to the cluster machine attributes for machines in the 'selectors' of the service.
  clusterServiceToMachineServices =
    config:
    update.machines config (
      clusterName: machineName: machineConfig:
      let

        services = config.domain.clusters."${clusterName}".services;

        # filter the service list for the ones that match the path of the current machine
        filteredServices = attrsets.filterAttrs (
          serviceName: serviceDefinition:
          let
            selectors = (filtersToPaths serviceDefinition.selectors clusterName config);
          in
          (lists.any (
            filter:
            assert filterFormatIsOk filter;
            filter == "domain.clusters.${clusterName}.machines.${machineName}"
          ) selectors)
        ) services;

        # resolve the filters in the selectors and roles to the machine names
        resolvedServices = forEachAttrIn filteredServices (
          serviceName: serviceDefinition:
          serviceDefinition
          // {
            name = serviceName;
            roles = (
              forEachAttrIn serviceDefinition.roles (
                roleName: role: (filters.resolveMachineName role clusterName config)
              )
            );
            selectors = filters.resolveMachineName serviceDefinition.selectors clusterName config;
          }
        );

      in
      {
        services = resolvedServices;
      }
    );

  # Takes all services defined on a __machine__ level, and adds the associated NixOs modules to the machines nixosModules (used to build the machine).
  machineServiceToNixOsConfiguration =
    config:
    add.nixosModule config (
      _clusterName: _machineName: machineConfig:
      let
        serviceModules = forEachAttrIn machineConfig.services (
          _serviceName: serviceDefinition: [
            serviceDefinition.definition
            serviceDefinition.extraConfig
          ]
        );
      in
      lists.flatten (attrsets.attrValues serviceModules)
    );

in
{
  config.extensions.transformations = {
    clusterTransformations = [ clusterServiceToMachineServices ];
    moduleTransformations = [ machineServiceToNixOsConfiguration ];
  };

}
