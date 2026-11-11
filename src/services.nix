{ lib, clusterlib, ... }:
let
  # imports
  attrsets = lib.attrsets;
  lists = lib.lists;

  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;

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
  # Selecting services for nodes is not a cluster transformation: it runs as a
  # dedicated pipeline step after the first node evaluation, so that selectors
  # can query evaluated machine options. See src/serviceSelection.nix and
  # doc/Decisions.md (D3).
  config.extensions.transformations = {
    moduleTransformations = [ nodeServiceToNixOsConfiguration ];
  };

}
