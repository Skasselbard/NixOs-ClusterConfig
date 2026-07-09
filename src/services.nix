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

  # Copies all services to the cluster node attributes for nodes in the 'selectors' of the service.
  clusterServiceToNodeServices =
    config:
    update.nodes config (
      clusterName: nodeName: nodeConfig:
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
            filter == "domain.clusters.${clusterName}.machines.${nodeName}"
            || filter == "domain.clusters.${clusterName}.vms.${nodeName}"
          ) selectors)
        ) services;

        # resolve the filters in the selectors and roles to the node names
        resolvedServices = forEachAttrIn filteredServices (
          serviceName: serviceDefinition:
          serviceDefinition
          // {
            name = serviceName;
            roles = (
              forEachAttrIn serviceDefinition.roles (
                roleName: role: (filters.resolveNodeName role clusterName config)
              )
            );
            selectors = filters.resolveNoedName serviceDefinition.selectors clusterName config;
          }
        );

      in
      {
        services = resolvedServices;
      }
    );

  # Takes all services defined on a __machine__ level, and adds the associated NixOs modules to the machines nixosModules (used to build the machine).
  nodeServiceToNixOsConfiguration =
    config:
    add.nixosModule config (
      _clusterName: _nodeName: nodeConfig:
      let
        serviceModules = forEachAttrIn nodeConfig.services (
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
    clusterTransformations = [ clusterServiceToNodeServices ];
    moduleTransformations = [ nodeServiceToNixOsConfiguration ];
  };

}
