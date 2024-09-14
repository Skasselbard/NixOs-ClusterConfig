{ pkgs, clusterlib, ... }:
let
  update = clusterlib.update;
  overwrite = clusterlib.overwrite;
in with pkgs.lib;

let
  # remove attributes from the config
  # used to build a serializable cluster info
  pruneusers = config:
    update.clusters config (clusterName: clusterConfig: {
      users = (attrsets.attrNames clusterConfig.users);
    });

  clusterInfoAnnotation = config:
    let
      machineInfo = overwrite.machines config
        (clusterName: machineName: machineConfig:
          machineConfig.annotations // {
            deployment.tags = machineConfig.deployment.tags;
            deployment.targetHost = machineConfig.deployment.targetHost;
            deployment.targetPort = machineConfig.deployment.targetPort;
          });
      serviceInfo = overwrite.services machineInfo
        (clusterName: serviceName: serviceConfig: serviceConfig.annotations);
      userInfo = pruneusers serviceInfo;

    in attrsets.recursiveUpdate config {

      # Generate a cluster config attribute that can be used to query config information
      # All leaves of the structure must be serializable; in particular: cannot be functions / lambdas
      clusterInfo.domain = userInfo.domain;

    };
in { config.extensions.deploymentTransformations = [ clusterInfoAnnotation ]; }
