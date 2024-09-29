{ pkgs, clusterlib, ... }:
let
  # imports
  asserts = pkgs.lib.asserts;
  strings = pkgs.lib.strings;
  attrsets = pkgs.lib.attrsets;
  lists = pkgs.lib.lists;

  filters = import ./filters.nix { lib = pkgs.lib; };

  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;
  eval = clusterlib.eval;
  update = clusterlib.update;
  filtersToPaths = filters.filtersToPaths;

  # assert filter properties and assemble error message
  filterFormatIsOk =
    filter:
    asserts.assertMsg (strings.hasPrefix "domain" filter) "Filter '${filter}' does not start with 'domain'. Filters need to be a path in the clusterConfig in the form like 'domain.clusterName.machineName'";

  # Copies all services to the cluster machine attributs for machines in the 'selectors' of the service.
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

      in
      {
        services = filteredServices;
      }
    );

  # Takes all services defined on a __machine__ level, calls its service closure in 'serviceName.definition' with all arguments, and adds the resulting NixOs modules to the machines nixosModules (used to build the machine).
  machineServiceToNixOsConfiguration =
    config:
    add.nixosModule config (
      clusterName: machineName: machineConfig:
      let
        serviceModules = forEachAttrIn machineConfig.services (
          serviceName: serviceDefinition: eval.service config clusterName serviceDefinition machineConfig
        );
      in
      lists.flatten (attrsets.attrValues serviceModules)
    );

in
{

  config.extensions = {
    clusterTransformations = [ clusterServiceToMachineServices ];
    moduleTransformations = [ machineServiceToNixOsConfiguration ];
  };

}
