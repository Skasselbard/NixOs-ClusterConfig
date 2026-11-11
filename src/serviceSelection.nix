# Internal service selection step.
#
# Copies the services declared for a cluster onto the nodes that their
# `selectors` resolve to, and resolves `roles` and `selectors` to node names on
# that node-local copy.
#
# This step used to be a `clusterTransformation`. It runs after the first node
# evaluation (`evalMachines`) instead, so that selectors can query evaluated
# machine options (`filters.machineOption`) without an additional evaluation
# round. See doc/Decisions.md (D3).
#
# `extensions.transformations` deliberately has no hook here: the position
# relative to the node evaluation is part of the pipeline contract, not a user
# extension point.
{ lib, clusterlib, filters }:
let
  # imports
  asserts = lib.asserts;
  strings = lib.strings;
  attrsets = lib.attrsets;
  lists = lib.lists;

  forEachAttrIn = clusterlib.forEachAttrIn;
  update = clusterlib.update;
  filtersToPaths = filters.filtersToPaths;

  # assert filter properties and assemble error message
  filterFormatIsOk =
    filter:
    asserts.assertMsg (strings.hasPrefix "domain" filter) "Filter '${filter}' does not start with 'domain'. Filters need to be a path in the clusterConfig in the form like 'domain.clusterName.machineName'";

in

# Copies all services to the cluster node attributes for nodes in the 'selectors' of the service.
config:
update.nodes config (
  clusterName: nodeName: _nodeConfig:
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
        selectors = filters.resolveNodeName serviceDefinition.selectors clusterName config;
      }
    );

  in
  {
    services = resolvedServices;
  }
)
