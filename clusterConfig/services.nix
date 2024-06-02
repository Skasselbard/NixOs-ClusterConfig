{ pkgs, lib, nixos-generators, clusterlib, ... }:
with pkgs.lib;
let # imports
  filters = import ./filters.nix {
    inherit clusterlib;
    lib = pkgs.lib;
  };

  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;
  get = clusterlib.get;

  # assert filter properties and assemble error message
  filterFormatIsOk = filter:
    asserts.assertMsg (strings.hasPrefix "domain" filter)
    "Filter '${filter}' does not start with 'domain'. Filters need to be a path in the clusterConfig in the form like 'domain.clusterName.machineName'";

  toConfigAttrPaths = filters: clusterName: config:
    lists.flatten (lists.forEach filters (filter: (filter clusterName config)));

  clusterServiceToMachineServices = config:
    add.machineConfiguration config (clusterName: machineName: machineConfig:
      let

        services = config.domain.clusters."${clusterName}".services;

        # filter the service list for the ones that match the path of the current machine
        filteredServices = attrsets.filterAttrs (serviceName: serviceDefinition:
          let
            selectors =
              (toConfigAttrPaths serviceDefinition.selectors clusterName
                config);
          in (lists.any (filter:
            assert filterFormatIsOk filter;
            filter == "domain.clusters.${clusterName}.machines.${machineName}")
            selectors)) services;

      in { services = filteredServices; });

  machineServiceToNixOsConfiguration = config:
    add.nixosModule config (clusterName: machineName: machineConfig:
      let
        services = machineConfig.services;
        serviceModules = forEachAttrIn services (serviceName: serviceDefinition:
          let
            selectors = (filters.resolve
              (toConfigAttrPaths serviceDefinition.selectors clusterName config)
              config);
            roles = (forEachAttrIn serviceDefinition.roles (filters.resolve
              (roleName: role: (toConfigAttrPaths role clusterName config))
              config));
            serviceModule = lib.evalModules {
              modules = [
                serviceDefinition.config
                {
                  config = {

                    # make serviceConfig available in the configuration
                    _module.args = {
                      serviceConfig = {
                        inherit selectors roles;
                        this = machineConfig.annotations;
                      };
                      inherit pkgs lib;
                    };

                    # DO NOT PANIC!!!
                    _module.check = false;

                  };
                }
              ];
            };
          in serviceModule);
      in serviceModules);

in {

  config.extensions = {
    clusterTransformations = [ clusterServiceToMachineServices ];
    # moduleTransformations = [ machineServiceToNixOsConfiguration ];
  };

}
