{ pkgs, nixos-generators, colmena, flake-utils, nixos-anywhere, clusterlib, ...
}:
let # imports
  filters = import ./filters.nix { lib = pkgs.lib; };

  forEachAttrIn = clusterlib.forEachAttrIn;
  add = clusterlib.add;
  get = clusterlib.get;

in with pkgs.lib;
let

  # Annotate all machines with data from the cluster config.
  # This includes:
  # - Hostnames: networking.hostname is set to the name of the machiene definition
  # - DomainName: networkinig.domain is set to clusterName.domainSuffix
  # - Hostplattform: pkgs.hostPlattform is set to the configured system in the machine configuration
  # clusterAnnotatedCluster = clusterAnnotation evaluatedCluster;
  # - UserDefinitions: users.users is set
  clusterAnnotation = config:

    # Add NixOs modules inferred by the cluster config to each Machines NixOs modules
    add.nixosModule config (clusterName: machineName: machineConfig:
      let

        clusterUsers = config.domain.clusters."${clusterName}".users;
        machineUsers = machineConfig.users;

      in [

        { # machine config
          networking.hostName = machineName;
          networking.domain = clusterName + "." + config.domain.suffix;
          nixpkgs.hostPlatform = mkDefault machineConfig.system;
        }

        # make different modules for cluster and user definitions so that the NixOs
        # module system handles the merging

        { # cluster users
          users.users =
            forEachAttrIn clusterUsers (n: userConfig: userConfig.systemConfig);
          # forEach user (homeManagerModules ++ userHMModules) -> if not empty -> enable HM
        }

        { # machine users
          users.users =
            forEachAttrIn machineUsers (n: userConfig: userConfig.systemConfig);
        }

      ]);

  # Add the service configurations to the modlues of the tergeted machines
  serviceAnnotation = with lists;
    config:
    let services = get.services config;
    in add.nixosModule config (clusterName: machineName: machineConfig:
      let

        # filter the service list for the ones that match the path of the current machine
        filteredServices = builtins.filter (service:
          (lists.any (filter:
            assert asserts.assertMsg (strings.hasPrefix "domain" filter)
              "Filter '${filter}' does not start with 'domain'. Filters need to be a path in the clusterConfig in the form like 'domain.clusterName.machineName'";
            filter == "domain.clusters.${clusterName}.machines.${machineName}")
            service.selectors)) services;

      in (lists.forEach filteredServices (service:
        # get the config closure and compute its result to form a complete NixosModule
        (service.config {
          selectors =
            service.selectors (filters.resolve service.selectors config);
          roles = service.roles;
          this = machineConfig.annotations; # machineConfig;
        }))));

  # Build the deployment scripts 
  deploymentAnnotation = config:
    let machines = get.machines config;
    in config // attrsets.recursiveUpdate {

      nixosConfigurations = forEachAttrIn machines
        (machineName: machineConfig: machineConfig.nixosConfiguration);

      colmena = {
        meta.nixpkgs = import nixpkgs {
          system = "x86_64-linux"; # TODO: is this used for all machines?
          overlays = [ ];
        };
      } // forEachAttrIn machines (machineName: machineConfig: {
        deployment = machineConfig.deployment;
        imports = machineConfig.nixosModules;
      });

      apps = colmena.apps;
      # TODO: clusterconfig app as default

    }
    # The deployment options are generated for all system  configurations (by using flake utils)

    (flake-utils.lib.eachSystem flake-utils.lib.allSystems (system: {

      # buld an iso package for each machine configuration 
      packages = forEachAttrIn machines (machineName: machineConfig: {
        iso = nixos-generators.nixosGenerate
          ((build.bootImageNixosConfiguration machineConfig) // {
            format = "iso";
          });
        setup = let
          nixosConfig =
            machineConfig.nixosConfiguration.config.system.build.toplevel.outPath;
          formatScript =
            machineConfig.nixosConfiguration.config.partitioning.ephemeral_script;
        in pkgs.writeScriptBin "deploy" ''
          ${pkgs.nix}/bin/nix run path:${nixos-anywhere.outPath} -- -s ${formatScript.outPath} ${nixosConfig} ${machineConfig.deployment.targetUser}@${machineConfig.deployment.targetHost}
        '';
      });

      # # build executables for deployment that can be run with 'nix run'
      # apps = forEachAttrIn machines (machineName: machineConfig: {
      #   "setup-${machineName}" = {
      #     type = "app";
      #     program = ? run nixos anywhere;
      #   };
      #   # "deploy-${machioneName}" = ? run colmena upload-keys; run nixos-rebuild;
      # });
    }));

in {

  config.extensions = {
    clusterTransformations = [ clusterAnnotation ];
    moduleTransformations = [ serviceAnnotation ];
    deploymentTransformations = [ deploymentAnnotation ];
  };

}
