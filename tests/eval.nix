{
  clusterLib,
  modules,
  lib,
  pkgs,
}:
let
  inherit (clusterLib) buildCluster filters;
  node = {
    system = "x86_64-linux";
    nixosModules = [
      {
        system.stateVersion = "25.05";
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };
        boot.loader.grub.device = "nodev";
      }
    ];
  };
  build = domain: buildCluster { inherit domain; };
  failed = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  baseDomain = {
    suffix = "example.com";
  };
  duplicate = build (
    baseDomain
    // {
      clusters.lab = {
        machines.same = node;
        vms.same = node // {
          host = "same.lab.example.com";
        };
      };
    }
  );
  dotted = build (baseDomain // { clusters."prod.us".machines.node = node; });
  dottedNode = build (baseDomain // { clusters.lab.machines."web.1" = node; });
  collision = build (
    baseDomain
    // {
      clusters = {
        "prod-west".machines.web = node;
        prod.machines."west-web" = node;
      };
    }
  );
  missingSelector = buildCluster {
    modules = [ modules.simple-dns ];
    domain = baseDomain // {
      clusters.lab = {
        machines.node = node;
        services.dns = {
          selectors = [ (filters.machineName "missing") ];
          roles.hosts = [ ];
        };
      };
    };
  };
  missingRole = buildCluster {
    modules = [ modules.simple-dns ];
    domain = baseDomain // {
      clusters.lab = {
        machines.node = node;
        services.dns = {
          selectors = [ ];
          roles.hosts = [ (filters.vmName "missing") ];
        };
      };
    };
  };
  cluster = buildCluster {
    modules = [
      modules.vms
      modules.simple-dns
      modules.nixos-anywhere
      ({ pkgs, clusterlib, ... }: {
        extensions.nodes.packages.shared = {
          description = "Shared test package";
          package =
            { clusterConfig }:
            pkgs.writeShellScriptBin "shared" "echo ${clusterConfig.clusters.this.name}";
        };
        extensions.machines.packages.machineOnly = {
          description = "Machine-only test package";
          action = "build";
          destructive = true;
          package =
            { clusterConfig }:
            pkgs.writeShellScriptBin "machineOnly" "echo ${clusterConfig.clusters.this.nodes.this.name}";
        };
        extensions.vms.packages.vmOnly = {
          description = "VM-only test package";
          package =
            { clusterConfig }:
            pkgs.writeShellScriptBin "vmOnly" "echo ${clusterConfig.clusters.this.nodes.this.name}";
        };
        extensions.nodes.packages.legacy =
          { clusterConfig }:
          clusterlib.describe "Legacy test package" (
            pkgs.writeShellScriptBin "legacy" "echo ${clusterConfig.clusters.this.name}"
          );
      })
    ];
    domain = baseDomain // {
      clusters = {
        alpha = {
          users.alphaUser.systemConfig.isNormalUser = true;
          machines.host = node // {
            deployment = {
              targetHost = "192.0.2.1";
              targetUser = "admin";
              targetPort = 2222;
              formatScript = pkgs.writeShellScript "format" "exit 0";
            };
          };
        };
        beta = {
          users.betaUser.systemConfig.isNormalUser = true;
          services.dns = {
            selectors = [ filters.clusterNodes ];
            roles.hosts = [ filters.clusterNodes ];
          };
          machines.other = node;
          vms.guest = node // {
            host = "host.alpha.example.com";
            backend.microvm = {
              vcpu = 2;
              mem = 1024;
              interfaces = [ { type = "user"; id = "test"; mac = "02:00:00:00:00:01"; } ];
            };
          };
        };
      };
    };
  };
  guest = cluster.nixosConfigurations.beta-guest.config;
  hosted = cluster.nixosConfigurations.alpha-host.config.microvm.vms.guest.evaluatedConfig.config;
  duplicateHost = buildCluster {
    modules = [ modules.vms ];
    domain = baseDomain // {
      clusters = {
        alpha.machines.host = node;
        beta.vms.guest = node // {
          host = "host.alpha.example.com";
        };
        gamma.vms.guest = node // {
          host = "host.alpha.example.com";
        };
      };
    };
  };
  arm = buildCluster {
    packageSystem = "aarch64-linux";
    domain = baseDomain // {
      clusters.lab.machines.node = node;
    };
  };
  conflictingPackages = buildCluster {
    modules = [
      ({ pkgs, ... }: {
        extensions.nodes.packages.same = { clusterConfig }: pkgs.hello;
        extensions.machines.packages.same = { clusterConfig }: pkgs.hello;
      })
    ];
    domain = baseDomain // {
      clusters.lab.machines.node = node;
    };
  };
  noForceIndex = buildCluster {
    modules = [
      ({ pkgs, ... }: {
        extensions.machines.packages.broken = {
          description = "Broken test package";
          package = throw "the package body must not be forced by the index";
        };
      })
    ];
    domain = baseDomain // {
      clusters.lab.machines.node = node;
    };
  };
  repeatNames = build (
    baseDomain
    // {
      clusters = {
        alpha.machines.node = node;
        beta.machines.node = node;
      };
    }
  );
  armTarget = build (
    baseDomain
    // {
      clusters.lab.machines.node = node // {
        system = "aarch64-linux";
      };
    }
  );
  sameCluster = buildCluster {
    modules = [
      modules.vms
      modules.simple-dns
    ];
    domain = baseDomain // {
      clusters.lab = {
        machines.host = node;
        vms.guest = node // {
          host = "host.lab.example.com";
        };
        services.dns = {
          selectors = [ filters.clusterNodes ];
          roles.hosts = [ filters.clusterNodes ];
        };
      };
    };
  };
  # A cluster that classifies its nodes with tags and labels and uses them for
  # service selection.
  taggedCluster = buildCluster {
    modules = [
      modules.vms
      {
        extensions.nodes.options.priority = lib.mkOption {
          description = "Test option used to select nodes by node option.";
          type = lib.types.int;
          default = 0;
        };
        extensions.clusterServices.demo = {
          defaultModule = { ... }: { };
          options = { };
          roles = [ "primary" ];
        };
      }
    ];
    domain = baseDomain // {
      clusters.lab = {
        machines = {
          web = node // {
            tags = [
              "prod"
              "web"
              "prod"
            ];
            labels.tier = "edge";
          };
          db = node // {
            tags = [
              "prod"
              "db"
            ];
            labels = {
              tier = "core";
              zone = "eu-west-1a";
            };
            priority = 10;
          };
          stage = node // {
            tags = [ "staging" ];
          };
        };
        vms.guest = node // {
          host = "web.lab.example.com";
          tags = [
            "prod"
            "web"
          ];
          labels.tier = "edge";
        };
        services.demo = {
          selectors = [ (filters.tagsAny "prod") ];
          roles.primary = [ (filters.tagsAll [ "prod" "db" ]) ];
        };
      };
    };
  };
  taggedView = taggedCluster.domain.clusters.lab;
  # Node names selected by a filter, sorted for stable comparisons.
  filterNames =
    filter:
    builtins.sort builtins.lessThan (
      map (path: lib.last (lib.splitString "." path)) (filter "lab" taggedCluster)
    );
  # A cluster whose service selectors query evaluated machine options.
  machineOptionCluster = buildCluster {
    modules = [
      {
        extensions.clusterServices.machineOnly = {
          defaultModule = { ... }: { };
          options = { };
        };
      }
    ];
    domain = baseDomain // {
      clusters.lab = {
        machines = {
          first = node;
          second = node;
        };
        services.machineOnly.selectors = [ (filters.machineOption [ "networking" "hostName" ] "second") ];
      };
    };
  };
  machineOptionView = machineOptionCluster.domain.clusters.lab;
  badTagCluster = build (
    baseDomain
    // {
      clusters.lab.machines.node = node // {
        tags = [ "bad tag" ];
      };
    }
  );
  badLabelKeyCluster = build (
    baseDomain
    // {
      clusters.lab.machines.node = node // {
        labels."bad key" = "value";
      };
    }
  );
  badLabelValueCluster = build (
    baseDomain
    // {
      clusters.lab.machines.node = node // {
        labels.tier = "edge/";
      };
    }
  );
  secretCluster = buildCluster {
    modules = [ modules.secret-service ];
    domain = baseDomain // {
      clusters.lab = {
        services.secrets = {
          selectors = [ filters.clusterMachines ];
          sopsRoot = ../examples/04-secretDeployment/secrets;
          adminKeySource.type = "native";
        };
        machines = {
          remote = node // {
            deployment = {
              targetHost = "192.0.2.50";
              targetUser = null;
              targetPort = 2222;
              secrets.keySource = { type = "age"; age.sourceKeyFile = "/tmp/test-age-key"; };
            };
          };
          local = node // {
            deployment = {
              targetHost = null;
              secrets.keySource = { type = "age"; age.sourceKeyFile = "/tmp/test-age-key"; };
            };
          };
        };
      };
    };
  };
  remoteKeyScript = secretCluster.packages.x86_64-linux.lab.remote.secretsInstallKey.text;
  localKeyScript = secretCluster.packages.x86_64-linux.lab.local.secretsInstallKey.text;
  emptySelector = buildCluster {
    modules = [ modules.simple-dns ];
    domain = baseDomain // {
      clusters.lab = {
        machines.node = node;
        services.dns = {
          selectors = [ ];
          roles.hosts = [ ];
        };
      };
    };
  };
  extensionCluster = buildCluster {
    modules = [
      ({ lib, ... }: {
        extensions.cluster.options.shared.deep.first = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "cluster-first" ];
        };
        extensions.nodes.options.shared.deep.first = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { name = "node-first"; };
        };
        extensions.clusterServices.demo = {
          defaultModule = { ... }: { };
          options.shared.deep.first = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "service-first";
          };
        };
      })
      ({ lib, ... }: {
        extensions.cluster.options.shared.deep.second = lib.mkOption {
          type = lib.types.str;
          default = "cluster-second";
        };
        extensions.nodes.options.shared.deep.second = lib.mkOption {
          type = lib.types.str;
          default = "node-second";
        };
        extensions.clusterServices.demo.options.shared.deep.second = lib.mkOption {
          type = lib.types.str;
          default = "service-second";
        };
      })
    ];
    domain = baseDomain // {
      clusters.lab = {
        machines.node = node // { shared.deep.second = "configured-node"; };
        shared.deep.second = "configured-cluster";
        services.demo = {
          selectors = [ filters.clusterNodes ];
          shared.deep.second = "configured-service";
        };
      };
    };
  };
  extensionView = extensionCluster.nixosConfigurations.lab-node.config.clusterConfig.clusters.this;
  optionDeclarations = declarations: (lib.evalModules {
    modules = [ ../src/options/extensionOptions.nix ] ++ declarations;
  }).config.extensions.nodes.options;
  duplicateOptionModules = [
    { _file = "first-extension.nix"; extensions.nodes.options.shared.value = lib.mkOption { type = lib.types.str; default = "a"; }; }
    { _file = "second-extension.nix"; extensions.nodes.options.shared.value = lib.mkOption { type = lib.types.str; default = "b"; }; }
  ];
  optionNamespaceModules = [
    { extensions.nodes.options.shared.value = lib.mkOption { type = lib.types.str; default = "a"; }; }
    { extensions.nodes.options.shared.value.child = lib.mkOption { type = lib.types.str; default = "b"; }; }
  ];
  optionDeclarationsIn = path: declarations: lib.attrByPath path null ((lib.evalModules {
    modules = [ ../src/options/extensionOptions.nix ] ++ declarations;
  }).config.extensions);
in
{
  tests = {
    qualifiedNames =
      builtins.attrNames repeatNames.nixosConfigurations == [
        "alpha-node"
        "beta-node"
      ];
    duplicateMachineVm = failed duplicate.nixosConfigurations;
    qualifiedCollision = failed collision.nixosConfigurations;
    dottedCluster = failed dotted.nixosConfigurations;
    dottedNode = failed dottedNode.nixosConfigurations;
    invalidSelector = failed missingSelector.nixosConfigurations;
    missingFilterPath = failed (filters.resolve [ (filters.machineName "missing") ] "lab" { domain.clusters.lab.machines = { }; });
    invalidRole = failed missingRole.nixosConfigurations;
    duplicateHostVm = failed duplicateHost.nixosConfigurations;
    crossClusterHosting = hosted.networking.extraHosts == guest.networking.extraHosts
      && builtins.elem "dns" guest.clusterConfig.clusters.this.nodes.this.services;
    sameClusterHosting =
      sameCluster.nixosConfigurations.lab-host.config.microvm.vms.guest.evaluatedConfig.config.networking.extraHosts
      == sameCluster.nixosConfigurations.lab-guest.config.networking.extraHosts;
    emptySelectorAllowed = builtins.attrNames emptySelector.nixosConfigurations == [ "lab-node" ];
    guestClusterUsers = hosted.users.users ? betaUser && !(hosted.users.users ? alphaUser);
    guestClusterDomain = hosted.networking.domain == "beta.example.com";
    configuredVmOptions =
      guest.microvm.vcpu == 2 && guest.microvm.mem == 1024
      && (builtins.head guest.microvm.interfaces).id == "test"
      && hosted.microvm.vcpu == guest.microvm.vcpu
      && (builtins.head hosted.microvm.interfaces).mac == "02:00:00:00:00:01";
    guestRole = builtins.length guest.clusterConfig.clusters.this.services.dns.roles.hosts == 2;
    hostHasNoGuestService = !(cluster.domain.clusters.alpha.machines.host.services ? dns);
    scopesMachine =
      cluster.packages.x86_64-linux.alpha.host ? shared
      && cluster.packages.x86_64-linux.alpha.host ? machineOnly
      && !(cluster.packages.x86_64-linux.alpha.host ? vmOnly);
    scopesVm =
      cluster.packages.x86_64-linux.beta.guest ? shared
      && cluster.packages.x86_64-linux.beta.guest ? vmOnly
      && !(cluster.packages.x86_64-linux.beta.guest ? machineOnly);
    noMachineDeployOnVm = !(cluster.packages.x86_64-linux.beta.guest ? deploy);
    qualifiedColmenaNames =
      let
        c = buildCluster {
          modules = [ modules.colmena ];
          domain = baseDomain // { clusters = { alpha.machines.node = node; beta.machines.node = node; }; };
        };
      in builtins.attrNames c.colmena == [ "alpha-node" "beta-node" "meta" ]
        && c.colmena.alpha-node.deployment.targetHost == "node";
    deployCommand =
      lib.hasInfix "--flake '.#alpha-host'" cluster.packages.x86_64-linux.alpha.host.deploy.text
      && lib.hasInfix "-p 2222" cluster.packages.x86_64-linux.alpha.host.deploy.text
      && lib.hasInfix "admin@192.0.2.1" cluster.packages.x86_64-linux.alpha.host.deploy.text;
    hardwareCommand = lib.hasInfix "ssh -p 2222 -t admin@192.0.2.1" cluster.packages.x86_64-linux.alpha.host.hardware-configuration.text;
    formatCommand =
      lib.hasInfix "ssh://admin@192.0.2.1:2222" cluster.packages.x86_64-linux.alpha.host.format.text
      && lib.hasInfix "ssh -p 2222 -t admin@192.0.2.1" cluster.packages.x86_64-linux.alpha.host.format.text;
    createCommand =
      lib.hasInfix "--ssh-port 2222" cluster.packages.x86_64-linux.alpha.host.create.text
      && lib.hasInfix "admin@192.0.2.1" cluster.packages.x86_64-linux.alpha.host.create.text
      && builtins.match ".* -s /nix/store/[^ ]+ /nix/store/[^ ]+ --ssh-port 2222 .*" (lib.replaceStrings [ "\n" ] [ " " ] cluster.packages.x86_64-linux.alpha.host.create.text) != null;
    helperBinaryNames =
      map (name: cluster.packages.x86_64-linux.alpha.host.${name}.name) [
        "build"
        "deploy"
        "hardware-configuration"
        "create"
        "format"
      ] == [
        "build"
        "deploy"
        "hardware-configuration"
        "create"
        "format"
      ];
    packageDescriptions =
      cluster.packages.x86_64-linux.alpha.host.shared.meta.description == "Shared test package"
      && cluster.packages.x86_64-linux.alpha.host.machineOnly.meta.description == "Machine-only test package"
      && cluster.packages.x86_64-linux.beta.guest.vmOnly.meta.description == "VM-only test package"
      && cluster.packages.x86_64-linux.alpha.host.build.meta.description == "Build the machine configuration locally with nixos-rebuild build";
    derivationMetadata =
      cluster.packages.x86_64-linux.alpha.host.iso.meta.clusterConfig.action == "build"
      && cluster.packages.x86_64-linux.alpha.host.create.meta.clusterConfig.destructive == true
      && cluster.packages.x86_64-linux.alpha.host.format.meta.clusterConfig.destructive == true
      && cluster.packages.x86_64-linux.alpha.host.machineOnly.meta.clusterConfig.action == "build"
      && cluster.packages.x86_64-linux.alpha.host.machineOnly.meta.clusterConfig.destructive == true;
    packageIndex =
      let
        entries = cluster.packageIndex.packages;
        find = path: builtins.head (builtins.filter (entry: entry.attrPath == path) entries);
      in
      (find "alpha.host.iso").action == "build"
      && (find "alpha.host.create").destructive == true
      && (find "alpha.host.shared").description == "Shared test package"
      && (find "alpha.host.legacy").description == ""
      && (find "clusterConfig").kind == "tool";
    appClusterConfig =
      cluster.apps ? x86_64-linux
      && cluster.apps.x86_64-linux ? clusterConfig
      && cluster.apps.x86_64-linux ? clcli
      && cluster.apps.x86_64-linux ? default
      && lib.hasInfix "/bin/clusterConfig" cluster.apps.x86_64-linux.default.program;
    flakeInfoOverview =
      cluster.flakeInfo.clusters.alpha.machines.host.type == "machine"
      && cluster.flakeInfo.clusters.beta.vms.guest.type == "vm"
      && cluster.flakeInfo.clusters.beta.services ? dns
      && cluster.flakeInfo.clusters.beta.services.dns.roles == [ "hosts" ]
      && builtins.any (
        entry: entry.name == "alpha-host" && entry.clusterName == "alpha" && entry.type == "machine"
      ) cluster.flakeInfo.nixosConfigurations;
    secretSshTarget = lib.hasInfix "-p 2222 192.0.2.50" remoteKeyScript && !(lib.hasInfix "root@192.0.2.50" remoteKeyScript);
    secretLocalInstall = lib.hasInfix "mkdir -p \"$(dirname /var/lib/sops-nix/key.txt)\"" localKeyScript && !(lib.hasInfix "StrictHostKeyChecking=accept-new" localKeyScript);
    packageSystem =
      arm.packages.aarch64-linux.lab.node.build.system == "aarch64-linux"
      && !(arm.packages ? x86_64-linux);
    isoTarget = armTarget.packages.x86_64-linux.lab.node.iso.system == "aarch64-linux";
    packageConflict = failed conflictingPackages.nixosConfigurations;
    packageIndexDoesNotForce =
      (builtins.head (
        builtins.filter (entry: entry.attrPath == "lab.node.broken") noForceIndex.packageIndex.packages
      )).description == "Broken test package";
    nestedClusterOptions =
      extensionView.shared.deep.first == [ "cluster-first" ]
      && extensionView.shared.deep.second == "configured-cluster";
    nestedNodeOptions =
      extensionView.nodes.this.shared.deep.first.name == "node-first"
      && extensionView.nodes.this.shared.deep.second == "configured-node";
    nestedServiceOptions =
      extensionView.services.demo.shared.deep.first == "service-first"
      && extensionView.services.demo.shared.deep.second == "configured-service";
    duplicateExtensionOption = failed (optionDeclarations duplicateOptionModules).shared.value;
    duplicateIdenticalExtensionOption = failed (optionDeclarations [
      { extensions.nodes.options.value = lib.mkOption { type = lib.types.str; default = "same"; }; }
      { extensions.nodes.options.value = lib.mkOption { type = lib.types.str; default = "same"; }; }
    ]).value;
    duplicateClusterExtensionOption = failed (optionDeclarationsIn [ "cluster" "options" "value" ] [
      { extensions.cluster.options.value = lib.mkOption { type = lib.types.str; default = "a"; }; }
      { extensions.cluster.options.value = lib.mkOption { type = lib.types.str; default = "b"; }; }
    ]);
    duplicateServiceExtensionOption = failed (optionDeclarationsIn [ "clusterServices" "demo" "options" "value" ] [
      { extensions.clusterServices.demo.options.value = lib.mkOption { type = lib.types.str; default = "a"; }; }
      { extensions.clusterServices.demo.options.value = lib.mkOption { type = lib.types.str; default = "b"; }; }
    ]);
    optionNamespaceConflict = failed (optionDeclarations optionNamespaceModules).shared.value;
    optionNamespaceConflictReversed = failed (optionDeclarations (lib.reverseList optionNamespaceModules)).shared.value;
    extensionOptionPriority =
      ((optionDeclarations [
        { extensions.nodes.options.shared.value = lib.mkDefault (lib.mkOption { type = lib.types.str; default = "default"; }); }
        { extensions.nodes.options.shared.value = lib.mkOption { type = lib.types.str; default = "override"; }; }
      ]).shared.value.default) == "override";

    # ── node tags, labels and node option filters ──
    tagsMergedAsSet = taggedView.machines.web.tags == [ "prod" "web" ];
    tagsAnySingle = filterNames (filters.tagsAny "prod") == [ "db" "guest" "web" ];
    tagsAnyListOne = filterNames (filters.tagsAny [ "prod" ]) == [ "db" "guest" "web" ];
    tagsAnyListMulti = filterNames (filters.tagsAny [ "prod" "staging" ]) == [ "db" "guest" "stage" "web" ];
    tagsAnySingleTag = filterNames (filters.tagsAny "staging") == [ "stage" ];
    tagsAllSingle = filterNames (filters.tagsAll "prod") == [ "db" "guest" "web" ];
    tagsAllList = filterNames (filters.tagsAll [ "prod" "db" ]) == [ "db" ];
    tagsAllListNoMatch = filterNames (filters.tagsAll [ "prod" "staging" ]) == [ ];
    tagsAnyEmpty = failed (filters.tagsAny [ ] "lab" taggedCluster);
    tagsAllEmpty = failed (filters.tagsAll [ ] "lab" taggedCluster);
    tagsAnyWrongType = failed (filters.tagsAny 5 "lab" taggedCluster);
    labelsAllSingle = filterNames (filters.labelsAll { tier = "edge"; }) == [ "guest" "web" ];
    labelsAllMultiple = filterNames (filters.labelsAll { tier = "core"; zone = "eu-west-1a"; }) == [ "db" ];
    labelsAllPartialMatch = filterNames (filters.labelsAll { tier = "edge"; zone = "eu-west-1a"; }) == [ ];
    labelsAnyMultiple = filterNames (filters.labelsAny { tier = "edge"; zone = "eu-west-1a"; }) == [ "db" "guest" "web" ];
    labelsAnyNoMatch = filterNames (filters.labelsAny { tier = "nowhere"; }) == [ ];
    labelsAnyEmpty = failed (filters.labelsAny { } "lab" taggedCluster);
    labelsAllWrongType = failed (filters.labelsAll "tier" "lab" taggedCluster);
    hasLabelFilter = filterNames (filters.hasLabel "zone") == [ "db" ];
    hasLabelFilterMissing = filterNames (filters.hasLabel "missing") == [ ];
    # A list of filters is a union without duplicates, first mention wins.
    filterUnionDeduplicated =
      map (path: lib.last (lib.splitString "." path)) (filters.filtersToPaths [ filters.clusterVms filters.clusterNodes ] "lab" taggedCluster)
      == [ "guest" "db" "stage" "web" ];
    nodeOptionCoreFilter = filterNames (filters.nodeOption [ "system" ] "x86_64-linux") == [ "db" "guest" "stage" "web" ];
    nodeOptionExtensionFilter = filterNames (filters.nodeOption [ "priority" ] 10) == [ "db" ];
    nodeOptionMissingPath = failed (filters.nodeOption [ "missing" ] 1 "lab" taggedCluster);
    taggedServiceSelection =
      builtins.attrNames taggedView.machines.web.services == [ "demo" ]
      && builtins.attrNames taggedView.vms.guest.services == [ "demo" ]
      && taggedView.machines.stage.services == { };
    taggedServiceResolution =
      let
        view = taggedCluster.nixosConfigurations.lab-web.config.clusterConfig.clusters.this.services.demo;
        names = selected: builtins.sort builtins.lessThan (map (node: node.name) selected);
      in
      names view.selectors == [ "db" "guest" "web" ]
      && names view.roles.primary == [ "db" ];
    tagsInClusterView =
      taggedCluster.nixosConfigurations.lab-web.config.clusterConfig.clusters.this.nodes.this.tags == [ "prod" "web" ]
      && taggedCluster.nixosConfigurations.lab-guest.config.clusterConfig.clusters.this.nodes.this.tags == [ "prod" "web" ];
    labelsInClusterView =
      taggedCluster.nixosConfigurations.lab-db.config.clusterConfig.clusters.this.nodes.this.labels == {
        tier = "core";
        zone = "eu-west-1a";
      };
    invalidTag = failed badTagCluster.nixosConfigurations;
    invalidLabelKey = failed badLabelKeyCluster.nixosConfigurations;
    invalidLabelValue = failed badLabelValueCluster.nixosConfigurations;

    # ── evaluated machine option filters ──
    machineOptionSelection =
      builtins.attrNames machineOptionView.machines.second.services == [ "machineOnly" ]
      && machineOptionView.machines.first.services == { };
    machineOptionMissingPath = failed (filters.machineOption [ "missing" ] 1 "lab" machineOptionCluster);
    machineOptionBeforeEvaluation = failed (
      filters.machineOption [ "networking" "hostName" ] "second" "lab" {
        domain.clusters.lab.machines.first = node;
      }
    );
  };
}
