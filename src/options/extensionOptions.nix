{ lib, ... }:

let

  mkOption = lib.mkOption;

  attrsOf = lib.types.attrsOf;
  listOf = lib.types.listOf;
  raw = lib.types.raw;
  str = lib.types.str;
  submodule = lib.types.submodule;

  # Closures used for late configuration values. These still receive the
  # evaluated clusterConfig and return an arbitrary value.
  scriptType = raw;

  # Package scopes are deliberately recursive. A scope can contain either a
  # declaration:
  #
  #   {
  #     description = "...";       # optional, defaults to ""
  #     longDescription = "...";   # optional
  #     action = "run";            # "run" or "build", defaults to "run"
  #     destructive = false;       # defaults to false
  #     package = { clusterConfig }: drv;
  #   }
  #
  # or a namespace of declarations, e.g. `certificates.generate`. Legacy
  # closure-style declarations are also accepted:
  #
  #   { clusterConfig }: drv
  #
  # A directly recursive typed option tree is possible, but forcing its type
  # description recurses infinitely (attrsOf description -> either description
  # -> attrsOf). Avoid that fragile custom type here; the package transformation
  # handles both leaves and namespaces and supplies metadata defaults.
  packageType = raw;

  # WORKAROUND for nixpkgs' `types.anything` merging option declarations.
  #
  # The `extensions.*.options` trees hold option *declarations* (`mkOption`
  # values), e.g. `extensions.nodes.options.deployment.targetHost`. With
  # `attrsOf anything`, merging recurses into every attribute set it finds,
  # including a `mkOption` value. Descending into a declaration forces its
  # internals, notably `option.type.functor.wrapped`, which nixpkgs 26.05
  # deprecated in favour of `nestedTypes.elemType`. That is what produced the
  # repeated warning during evaluation:
  #
  #   evaluation warning: The deprecated `functor.wrapped` attribute is
  #   accessed, use `nestedTypes.elemType` instead.
  #
  # Recursing into an option declaration is not intended behaviour: to the
  # module system a declaration is an opaque value, and only the surrounding
  # namespaces are meant to be merged. `types.anything` cannot express that
  # distinction, so this type stops the recursion at the first declaration and
  # keeps merging plain attribute sets, which is what extensions need to let
  # several modules contribute options to the same namespace.
  #
  # Deliberately a little stricter than before: two declarations of the same
  # option path now fail with an explicit error instead of silently merging
  # their (deprecated) type internals. Repeated identical declarations were
  # never meaningful, and nixpkgs' own option merging rejects them too.
  #
  # Remove this once `extensions.*.options` no longer has to be merged through
  # a permissive type, or once nixpkgs drops the `functor.wrapped` deprecation.
  optionTreeValueWorkaround = lib.types.mkOptionType {
    name = "extensionOptionTreeValue";
    description = "extension option declaration or namespace";
    check = _: true;
    merge =
      loc: defs:
      let
        values = map (def: def.value) defs;
      in
      if lib.any lib.isOption values then
        if builtins.length defs == 1 then
          builtins.head values
        else
          throw "Conflicting extension option declarations at `${lib.showOption loc}' (defined in ${lib.concatStringsSep ", " (map (def: def.file) defs)})."
      else if lib.all (value: builtins.isAttrs value && !lib.isStringLike value) values then
        (attrsOf optionTreeValueWorkaround).merge loc defs
      else
        lib.types.anything.merge loc defs;
  };

  extensionType = {

    cluster = {

      options = mkOption {
        description = ''
          A set of options that are added to the cluster-config options.
          These can be used in cluster config scripts and are added to the cluster annotations
        '';
        default = { };

        type = attrsOf optionTreeValueWorkaround;
      };

      late.config = mkOption {
        description = ''
          A set of cluster options that will be set after the machine configurations were fully evaluated.
          For example to use in scripts that need information from the final machine configurations.
          The options have to be defined in the extension options.
          Closure of type {clusterConfig}: value.
          For evaluation, this closure will be called with an evaluated representation of the Cluster Config.
        '';
        type = attrsOf scriptType;
        default = { };
      };

      packages = mkOption {
        description = ''
          A set of packages (e.g. executable scripts) that will be made available to the flake packages.
          Build the package with: ``nix build .#<clusterName>.<packageName>``
          Package declaration with `description`, `action`, `destructive`, and
          a `package` closure of type {clusterConfig}: <derivation>.
        '';
        type = attrsOf packageType;
        default = { };
      };

    };

    nodes = {

      options = mkOption {
        description = ''
          A set of options that are added to the cluster-config-machine-options.
          These can be used in cluster config scripts and are added to the machine annotations
        '';
        default = { };

        type = attrsOf optionTreeValueWorkaround;
      };

      nixosModules = mkOption {
        description = ''
          A list of NixOs modules that are added to the machine's NixOs configuration.
        '';
        type = listOf raw;
        default = [ ];
      };

      late.config = mkOption {
        description = ''
          A set of cluster machine options that will be set after the machine configurations were fully evaluated.
          For example to use in scripts that need information from the final machine configurations.
          The options have to be defined in the extension options.
          Closure of type {clusterConfig}: value.
          For evaluation, this closure will be called with an evaluated representation of the Cluster Config.
        '';
        type = attrsOf scriptType;
        default = { };
      };

      packages = mkOption {
        description = ''
          A set of packages (e.g. executable scripts) that will be made available to the flake packages.
          Build the package with: ``nix build .#<clusterName>.<machineName>.<packageName>``
          Run the package with: ``nix run .#<clusterName>.<machineName>.<packageName>``
          Package declaration with `description`, `action`, `destructive`, and
          a `package` closure of type {clusterConfig}: <derivation>.
        '';
        type = attrsOf packageType;
        default = { };
      };

      # TODO: apps

    };

    machines.packages = mkOption {
      description = "Packages generated only for standalone machines.";
      type = attrsOf packageType;
      default = { };
    };

    vms.packages = mkOption {
      description = "Packages generated only for virtual machines.";
      type = attrsOf packageType;
      default = { };
    };

    clusterServices = mkOption {
      description = ''
        A set of cluster services that should be enabled in the cluster.

        The keys are the names of the services and the values are the service configurations.
      '';
      type = attrsOf (submodule {
        options = {

          defaultModule = mkOption {
            description = ''
              The root NixOs module of the service.
            '';
            type = raw;
          };

          roles = mkOption {
            description = ''
              A set of role names a machine can be assigned to.
              The service config can depend on the role(s) of a machine so that the service configuration can be adapted accordingly
            '';
            type = listOf str;
            default = [ ];
          };

          options = mkOption {
            description = ''
              A set of options that can be used e.g. to give service scripts additional information.
            '';
            default = { };
            type = attrsOf optionTreeValueWorkaround;
          };

          late.config = mkOption {
            description = ''
              A set of cluster service options that will be set after the machine configurations were fully evaluated.
              For example to use in scripts that need information from the final machine configurations.
              The options have to be defined in the extension options.
              Closure of type {clusterConfig}: value.
              For evaluation, this closure will be called with an evaluated representation of the Cluster Config.
            '';
            type = attrsOf scriptType;
            default = { };
          };

          packages = mkOption {
            description = ''
              A set of packages (e.g. executable scripts) that will be made available to the flake packages.
              Build the package with: ``nix build .#<clusterName>.<serviceName>.<packageName>``
              Run the package with: ``nix run .#<clusterName>.<serviceName>.<packageName>``
              Package declaration with `description`, `action`, `destructive`, and
              a `package` closure of type {clusterConfig}: <derivation>.
            '';
            type = attrsOf packageType;
            default = { };
          };

        };
      });
      default = { };

    };
    transformations = {

      hostTransformations = mkOption {
        description = "Transform hosts after final guest configurations are available.";
        type = listOf raw;
        default = [ ];
      };

      clusterTransformations = mkOption {
        description = ''
          A list of functions that takes a clusterConfig and returns a clusterConfig.

          These functions get called after the first cluster evaluation.
          In this step, information declared in the cluster options can be transformed and used for annotations.
          The machine NixOsModules are unevaluated at this point, so nothing that is
          derived from an evaluated node configuration is available.

          Services are selected after the first node evaluation, so ``node.services``
          is not populated in this step. Use ``selectors`` or ``roles`` instead of
          computing service membership here.

          For example, in this step, the default clusterConfig workflow takes the names of all defined machines
          and sets the ``networking.hostname`` option for each machine.
        '';
        type = listOf raw;
        default = [ ];
      };

      moduleTransformations = mkOption {
        description = ''
          A list of functions that takes a clusterConfig and returns a clusterConfig.

          These functions get called after the NixOsConfiguration for each machine was evaluated for the first time
          and the networking annotations (ips and fqdns) where set.
          In this step, cluster and machine information can be used to modify the cluster config.
          After this step, the NixOsModules for each machine will be evaluated once again.

          Services are selected before this step, so ``node.services`` holds the
          services that were selected for each node.

          For example, in this step, the default clusterConfig workflow takes the service and user configuration
          from the cluster and adds them to the nixOsModules of each machine.
        '';
        type = listOf raw;
        default = [ ];
      };

      deploymentTransformations = mkOption {
        description = ''
          A list of functions that takes a clusterConfig and returns a clusterConfig.

          These functions get called after the NixOsConfiguration evaluation.
          In this step, the cluster configuration can be annotated with additional scripts,
          based on the NixOsConfiguration from each machine.

          For example, in this step, the default clusterConfig workflow takes all machine configurations
          and adds deployment attributes, like a nixosConfigurations attribute that can be used in a flakes,
          to the configuration.
        '';
        type = listOf raw;
        default = [ ];
      };

      infoTransformations = mkOption {
        description = ''
          A list of functions that takes a clusterConfig and returns a clusterConfig.

          These functions get called after as a final evaluation.
          In this step, the generated flake can be extended with information attributes.
          These attributes should not alter the cluster configuration itself but only
          extract information.

          For example, in this step, the default clusterConfig workflow takes generates serializable
          cluster information that can be printed out.
        '';
        type = listOf raw;
        default = [ ];
      };

    };
  };

in
{
  options = {
    extensions = extensionType;
  };
  config = {

  };
}
