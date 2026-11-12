{ lib, clusterlib, ... }:
let # imports

  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;
  eval = clusterlib.eval;
  update = clusterlib.update;

  attrsets = lib.attrsets;
  mkDefault = lib.mkDefault;

  # helperFunctions

  # Detect if a value looks like a function expecting clusterConfig.
  # A valid function must accept an attrset and must reference "clusterConfig"
  # inside the parameter set definition.
  isClusterConfigFn =
    fn:
    builtins.isFunction fn
    && (builtins.elem "clusterConfig" (builtins.attrNames (builtins.functionArgs fn)));

  # Recursively traverse arbitrary attrsets.
  # - If attrset → recurse
  # - If is function expecting clusterConfig → call it
  # - Else → warn and drop
  callLeafFunctions =
    { clusterConfig, node }:
    if builtins.isAttrs node then
      # Recurse through all attributes of the attrset
      builtins.mapAttrs (
        _: child:
        callLeafFunctions {
          inherit clusterConfig;
          node = child;
        }
      ) node
    else if isClusterConfigFn node then
      # Call the function with the clusterConfig argument
      node { inherit clusterConfig; }
    else
      throw "ERROR: Value '${toString node}' is not a function expecting { clusterConfig, ... }.";

  # Add NixOs modules inferred by the cluster config to each nodes NixOs modules
  # This includes:
  # - HostNames: networking.hostname is set to the name of the node definition
  # - DomainName: networking.domain is set to clusterName.domainSuffix
  # - HostPlatform: pkgs.hostPlatform is set to the configured system in the node configuration
  # - UserDefinitions: users.users is set with information from cluster-users and node-users
  clusterTransformation =
    config:

    add.nixosModule config (
      clusterName: nodeName: nodeConfig:
      let

        clusterUsers = config.domain.clusters."${clusterName}".users;
        nodeUsers = nodeConfig.users;

      in
      [
        {
          # make clusterlib available for node and service configs
          _module.args = {
            inherit clusterlib;
          };
        }

        {
          # add options for the config that is set by the cluster config
          imports = [ ((import ./options/nixosOptions.nix) { inherit config clusterlib; }) ];
        }

        {
          # node config
          networking.hostName = nodeName;
          networking.domain = clusterName + "." + config.domain.suffix;
          nixpkgs.hostPlatform = mkDefault nodeConfig.system;
        }

        # make different modules for cluster and user definitions so that the NixOs
        # module system handles the merging

        {
          # cluster users
          users.users = forEachAttrIn clusterUsers (n: userConfig: userConfig.systemConfig);
          # forEach user (homeManagerModules ++ userHMModules) -> if not empty -> enable HM
        }

        {
          # node users
          users.users = forEachAttrIn nodeUsers (n: userConfig: userConfig.systemConfig);
        }

      ]
    );

  moduleTransformation =
    config:

    add.nixosModule config (
      clusterName: nodeName: nodeConfig: [
        {
          # make the cluster config available in in the ``config`` attribute during node evaluation
          clusterConfig = (eval.clusterConfig config { inherit clusterName nodeName; });
        }
      ]
    );

  lateConfigTransformation =
    config:

    lib.foldl (acc: elem: attrsets.recursiveUpdate acc elem) config [

      (update.clusters config (
        clusterName: clusterConfig:

        forEachAttrIn config.extensions.cluster.late.config (
          configName: configClosure:

          # call the closure with the evaluated cluster config representation
          callLeafFunctions {
            node = configClosure;
            clusterConfig = (eval.clusterConfig config { inherit clusterName; });
          }
        )
      ))

      (update.services config (
        clusterName: serviceName: serviceConfig:

        forEachAttrIn config.extensions.clusterServices."${serviceName}".late.config (
          configName: configClosure:

          # call the closure with the evaluated cluster config representation
          callLeafFunctions {
            node = configClosure;
            clusterConfig = (eval.clusterConfig config { inherit clusterName; });
          }
        )
      ))

      (update.nodes config (
        clusterName: nodeName: nodeConfig:

        forEachAttrIn config.extensions.nodes.late.config (
          configName: configClosure:

          # call the closure with the evaluated cluster config representation
          callLeafFunctions {
            node = configClosure;
            clusterConfig = (eval.clusterConfig config { inherit clusterName nodeName; });
          }
        )
      ))

    ];

  packageIndexTransformation =
    config:
    let
      isPackageDeclaration = value: builtins.isAttrs value && value ? package;

      genericMetadata = {
        description = "";
        longDescription = null;
        action = "run";
        destructive = false;
      };

      metadataOf =
        value:
        if isPackageDeclaration value || (builtins.isAttrs value && value ? description) then
          {
            description = value.description or "";
            longDescription = value.longDescription or null;
            action = value.action or "run";
            destructive = value.destructive or false;
          }
        else
          genericMetadata;

      entryFor =
        {
          kind,
          clusterName,
          group,
          segments,
          value,
        }:
        let
          metadata = metadataOf value;
        in
        {
          attrPath = builtins.concatStringsSep "." segments;
          inherit (metadata) description longDescription action destructive;
          inherit
            kind
            clusterName
            group
            segments
            ;
          packageName = lib.last segments;
        };

      entriesFor =
        {
          kind,
          clusterName,
          group ? null,
          baseSegments,
          packages,
        }:
        let
          walk =
            segments: value:
            if isPackageDeclaration value || builtins.isFunction value || !(builtins.isAttrs value) then
              [
                (entryFor {
                  inherit
                    kind
                    clusterName
                    group
                    segments
                    value
                    ;
                })
              ]
            else
              lib.concatMap (
                name: walk (segments ++ [ name ]) value.${name}
              ) (builtins.attrNames value);
        in
        lib.concatMap (
          name: walk (baseSegments ++ [ name ]) packages.${name}
        ) (builtins.attrNames packages);

      scopedNodePackages =
        scope: _nodeName:
        config.extensions.nodes.packages // config.extensions.${scope}.packages;

      clusterEntries =
        clusterName:
        let
          cluster = config.domain.clusters.${clusterName};
        in
        entriesFor {
          kind = "cluster";
          inherit clusterName;
          baseSegments = [ clusterName ];
          packages = config.extensions.cluster.packages;
        }
        ++ lib.concatMap (
          nodeName:
          entriesFor {
            kind = "machine";
            inherit clusterName;
            group = nodeName;
            baseSegments = [
              clusterName
              nodeName
            ];
            packages = scopedNodePackages "machines" nodeName;
          }
        ) (builtins.attrNames (cluster.machines or { }))
        ++ lib.concatMap (
          nodeName:
          entriesFor {
            kind = "vm";
            inherit clusterName;
            group = nodeName;
            baseSegments = [
              clusterName
              nodeName
            ];
            packages = scopedNodePackages "vms" nodeName;
          }
        ) (builtins.attrNames (cluster.vms or { }))
        ++ lib.concatMap (
          serviceName:
          entriesFor {
            kind = "service";
            inherit clusterName;
            group = serviceName;
            baseSegments = [
              clusterName
              serviceName
            ];
            packages = config.extensions.clusterServices.${serviceName}.packages;
          }
        ) (builtins.attrNames config.extensions.clusterServices);

      declaredEntries = lib.concatMap clusterEntries (builtins.attrNames config.domain.clusters);
      declaredPaths = builtins.listToAttrs (
        map (entry: {
          name = entry.attrPath;
          value = true;
        }) declaredEntries
      );

      packageOutput = config.packages.${config.packageSystem} or { };
      clusterNames = builtins.attrNames config.domain.clusters;

      declaredGroupKinds = builtins.listToAttrs (
        map (entry: {
          name = "${entry.clusterName}.${builtins.elemAt entry.segments 1}";
          value = if builtins.length entry.segments == 2 then "leaf" else "namespace";
        }) (builtins.filter (entry: builtins.length entry.segments >= 2) declaredEntries)
      );

      genericEntry =
        {
          kind,
          clusterName ? null,
          group ? null,
          metadata ? { },
          segments,
        }:
        entryFor {
          inherit
            kind
            clusterName
            group
            segments
            ;
          value = metadata;
        };

      extraEntries =
        lib.concatMap (
          topLevel:
          if builtins.elem topLevel clusterNames then
            let
              groups = packageOutput.${topLevel} or { };
            in
            lib.concatMap (
              groupName:
              let
                groupKey = "${topLevel}.${groupName}";
                groupKind = declaredGroupKinds.${groupKey} or "leaf";
                group = groups.${groupName} or { };
              in
              if groupKind == "namespace" then
                lib.concatMap (
                  packageName:
                  let
                    attrPath = "${topLevel}.${groupName}.${packageName}";
                  in
                  if builtins.hasAttr attrPath declaredPaths then
                    [ ]
                  else
                    [
                      (genericEntry {
                        kind = "cluster";
                        clusterName = topLevel;
                        segments = [
                          topLevel
                          groupName
                          packageName
                        ];
                      })
                    ]
                ) (builtins.attrNames group)
              else if builtins.hasAttr groupKey declaredPaths then
                [ ]
              else if builtins.isAttrs group && builtins.attrNames group == [ ] then
                [ ]
              else
                [
                  (genericEntry {
                    kind = "cluster";
                    clusterName = topLevel;
                    segments = [
                      topLevel
                      groupName
                    ];
                  })
                ]
            ) (builtins.attrNames groups)
          else if builtins.hasAttr topLevel declaredPaths then
            [ ]
          else
            [
              (genericEntry ({
                kind = if topLevel == "clusterConfig" || topLevel == "clcli" then "tool" else "package";
                segments = [ topLevel ];
              } // lib.optionalAttrs (topLevel == "clusterConfig" || topLevel == "clcli") {
                metadata = {
                  description = "ClusterConfig command-line interface";
                };
              }))
            ]
        ) (builtins.attrNames packageOutput);

      entries = lib.sort (a: b: a.attrPath < b.attrPath) (declaredEntries ++ extraEntries);
    in
    config
    // {
      packageIndex = {
        schemaVersion = 1;
        system = config.packageSystem;
        packages = entries;
      };
    };

  flakeInfoTransformation =
    config:
    let
      # Node values can depend on their own evaluated nixosConfiguration (for
      # example through a self-referencing targetHost or secret definition).
      # Keep the overview non-forcing: use node names and declared service roles.
      nodeSummary = type: _node: { inherit type; };

      serviceSummary =
        service:
        {
          roles = service.roles or [ ];
        };

      clusterSummary =
        cluster:
        {
          machines = lib.mapAttrs (_: nodeSummary "machine") (cluster.machines or { });
          vms = lib.mapAttrs (_: nodeSummary "vm") (cluster.vms or { });
          services = lib.mapAttrs (_: serviceSummary) config.extensions.clusterServices;
        };

      nixosConfigurations =
        lib.concatMap (
          clusterName:
          let
            cluster = config.domain.clusters.${clusterName};
            entriesFor =
              type: nodes:
              lib.mapAttrsToList (nodeName: _: {
                name = "${clusterName}-${nodeName}";
                inherit clusterName nodeName type;
              }) nodes;
          in
          entriesFor "machine" (cluster.machines or { })
          ++ entriesFor "vm" (cluster.vms or { })
        ) (builtins.attrNames config.domain.clusters);
    in
    config
    // {
      flakeInfo = {
        schemaVersion = 1;
        system = config.packageSystem;
        suffix = config.domain.suffix;
        clusters = lib.mapAttrs (_: clusterSummary) config.domain.clusters;
        inherit nixosConfigurations;
      };
    };



  packageTransformation =
    config:
    let
      isPackageDeclaration = value: builtins.isAttrs value && value ? package;

      packageMeta =
        value:
        {
          clusterConfig = {
            action = value.action or "run";
            destructive = value.destructive or false;
          };
        }
        // lib.optionalAttrs ((value.description or "") != "") {
          description = value.description;
        }
        // lib.optionalAttrs ((value.longDescription or null) != null) {
          longDescription = value.longDescription;
        };

      evalPackage =
        { clusterConfig, value }:
        let
          evaluate =
            body:
            if builtins.isFunction body then
              if isClusterConfigFn body then
                body { inherit clusterConfig; }
              else
                throw "ERROR: Package value is not a function expecting { clusterConfig, ... }."
            else
              body;
        in
        if isPackageDeclaration value then
          clusterlib.describe (packageMeta value) (evaluate value.package)
        else if builtins.isFunction value then
          evaluate value
        else if builtins.isAttrs value then
          builtins.mapAttrs (_: child: evalPackage { inherit clusterConfig; value = child; }) value
        else
          value;

      scopedPackages =
        scope: clusterName: nodeName:
        let
          common = config.extensions.nodes.packages;
          specific = config.extensions.${scope}.packages;
          conflicts = builtins.filter (name: builtins.hasAttr name specific) (builtins.attrNames common);
        in
        if conflicts != [ ] then
          throw "clusterConfig: conflicting ${scope} and node packages: ${builtins.concatStringsSep ", " conflicts}"
        else
          forEachAttrIn (common // specific) (
            _: value:
            evalPackage {
              inherit value;
              clusterConfig = eval.clusterConfig config { inherit clusterName nodeName; };
            }
          );
    in
    lib.foldl (acc: elem: attrsets.recursiveUpdate acc elem) config (
      [

        # Add a package for each cluster to the flake output
        (add.clusterPackage config (
          clusterName:

          # For each package declaration a package is added
          forEachAttrIn config.extensions.cluster.packages (
            _: value:
            evalPackage {
              inherit value;
              clusterConfig = (eval.clusterConfig config { inherit clusterName; });
            }
          )
        ))

        # Add a package for each node to the flake output
        (add.machinePackages config (scopedPackages "machines"))
        (add.vmPackages config (scopedPackages "vms"))

      ]
      ++ (lib.attrValues (
        # For all services the package extensions are evaluated
        forEachAttrIn config.extensions.clusterServices (
          serviceName: serviceDefinition:

          # Add a package for each service to the flake output
          (add.servicePackages config serviceName (
            clusterName:

            (forEachAttrIn serviceDefinition.packages (
              _: value:
              evalPackage {
                inherit value;
                clusterConfig = (eval.clusterConfig config { inherit clusterName; });
              }
            ))
          ))
        )
      ))
    );

  nixosModuleTransformations =
    config:
    add.nixosModule config (
      _: _: _:
      config.extensions.nodes.nixosModules
    );

in
{

  config.extensions.transformations = {

    clusterTransformations = [ clusterTransformation ];

    moduleTransformations = [
      moduleTransformation
      nixosModuleTransformations
    ];

    deploymentTransformations = [
      # order is important
      lateConfigTransformation
      packageTransformation
      packageIndexTransformation
      flakeInfoTransformation
    ];

  };

}
