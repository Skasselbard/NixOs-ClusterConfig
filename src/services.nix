{ pkgs, lib, nixos-generators, clusterlib, ... }:
with pkgs.lib;
let # imports
  filters = import ./filters.nix { lib = pkgs.lib; };

  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;
  update = clusterlib.update;
  get = clusterlib.get;
  filtersToPaths = filters.filtersToPaths;

  # assert filter properties and assemble error message
  filterFormatIsOk = filter:
    asserts.assertMsg (strings.hasPrefix "domain" filter)
    "Filter '${filter}' does not start with 'domain'. Filters need to be a path in the clusterConfig in the form like 'domain.clusterName.machineName'";

  clusterServiceToMachineServices = config:
    update.machines config (clusterName: machineName: machineConfig:
      let

        services = config.domain.clusters."${clusterName}".services;

        # filter the service list for the ones that match the path of the current machine
        filteredServices = attrsets.filterAttrs (serviceName: serviceDefinition:
          let
            selectors =
              (filtersToPaths serviceDefinition.selectors clusterName config);
          in (lists.any (filter:
            assert filterFormatIsOk filter;
            filter == "domain.clusters.${clusterName}.machines.${machineName}")
            selectors)) services;

      in { services = filteredServices; });

  machineServiceToNixOsConfiguration = config:
    add.nixosModule config (clusterName: machineName: machineConfig:
      let
        serviceModules = forEachAttrIn machineConfig.services
          (serviceName: serviceDefinition:
            let
              selectors =
                (filters.resolve serviceDefinition.selectors clusterName
                  config);
              roles = (forEachAttrIn serviceDefinition.roles
                (roleName: role: (filters.resolve role clusterName config)));
              serviceModule = [
                serviceDefinition.extraConfig
                (serviceDefinition.definition {
                  inherit selectors roles;
                  this = machineConfig.annotations;
                })
              ];
            in serviceModule);
      in lists.flatten (attrsets.attrValues serviceModules));

in {

  config.extensions = {
    clusterTransformations = [ clusterServiceToMachineServices ];
    moduleTransformations = [ machineServiceToNixOsConfiguration ];
  };

}
