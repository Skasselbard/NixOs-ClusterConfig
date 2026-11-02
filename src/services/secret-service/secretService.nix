{ service, machine, clusterName, machineName }:
{
  config,
  lib,
  pkgs,
  ...
}:

let

  inherit (builtins)
    attrNames
    attrValues
    concatMap
    filter
    hasAttr
    isFunction
    ;

  inherit (lib)
    concatStringsSep
    escapeShellArg
    mapAttrsToList
    mkBefore
    mkDefault
    mkIf
    optionalAttrs
    unique
    ;

  secretLib = import ./lib.nix { inherit lib pkgs; };

  clusterSecrets = service.secrets or { };
  machineSecrets = builtins.removeAttrs (machine.secrets or { }) [ "templates" ];
  machineTemplates = (machine.secrets or { }).templates or { };
  clusterTemplates = service.templates or { };

  mkSecret =
    scope: user: secretName: secret:
    let
      sopsFileRaw = secretLib.secretSopsFile {
        inherit
          service
          clusterName
          scope
          secret
          ;
        machineName = if scope == "machine" then machineName else null;
      };
      sopsFile =
        if builtins.isString sopsFileRaw && lib.hasPrefix "/nix/store/" sopsFileRaw then
          /. + (builtins.unsafeDiscardStringContext sopsFileRaw)
        else if builtins.isString sopsFileRaw && lib.hasPrefix "/" sopsFileRaw then
          /. + sopsFileRaw
        else
          sopsFileRaw;
      key = if secret.key != null then secret.key else "${user}/${secretName}";
      runtimeName = if secret.name != null then secret.name else "${user}/${secretName}";
      name = "${clusterName}/${user}/${secretName}";
      neededForUsers = secret.neededForUsers or false;
      owner = if neededForUsers then null else (if secret.owner != null then secret.owner else user);
      path =
        if secret.path != null then
          secret.path
        else if neededForUsers then
          "/run/secrets-for-users/${runtimeName}"
        else
          "/run/secrets/${runtimeName}";
    in
    {
      inherit name;
      value =
        {
          inherit
            sopsFile
            key
            name
            path
            ;
          mode = secret.mode;
          inherit (secret) restartUnits reloadUnits neededForUsers;
        }
        // optionalAttrs (owner != null) { inherit owner; }
        // optionalAttrs (secret.group != null) { group = secret.group; }
        // optionalAttrs (secret.format != null) { format = secret.format; };
    };

  clusterEntries = concatMap (
    user:
    map (
      secretName:
      mkSecret "cluster" user secretName clusterSecrets.${user}.${secretName}
    ) (
      filter (
        secretName:
        secretLib.clusterSecretVisibleToMachine {
          inherit service machineName;
          secret = clusterSecrets.${user}.${secretName};
        }
      ) (attrNames clusterSecrets.${user})
    )
  ) (attrNames clusterSecrets);

  machineEntries = concatMap (
    user:
    mapAttrsToList (secretName: secret: mkSecret "machine" user secretName secret) machineSecrets.${user}
  ) (attrNames machineSecrets);

  entryName = entry: "${entry.value.sopsFile}:${entry.value.key}";
  duplicateKeys =
    let
      names = map entryName (clusterEntries ++ machineEntries);
    in
    filter (name: builtins.length (filter (other: other == name) names) > 1) (unique names);

  clusterEntryAttrs = builtins.listToAttrs (
    map (entry: {
      name = entry.name;
      value = entry.value;
    }) clusterEntries
  );
  machineEntryAttrs = builtins.listToAttrs (
    map (entry: {
      name = entry.name;
      value = entry.value;
    }) machineEntries
  );

  shadowed = filter (name: hasAttr name machineEntryAttrs) (attrNames clusterEntryAttrs);
  effectiveSecrets = clusterEntryAttrs // machineEntryAttrs;

  formatsByFile = builtins.foldl' (
    acc: entry:
    let
      format = entry.value.format or null;
      file = entry.value.sopsFile;
    in
    if format == null then
      acc
    else
      acc // { ${file} = unique ((acc.${file} or [ ]) ++ [ format ]); }
  ) { } (attrValues effectiveSecrets);
  formatConflicts = builtins.filter (file: builtins.length formatsByFile.${file} > 1) (
    attrNames formatsByFile
  );

  ownerGroupAssertions = concatMap (
    entry:
    [
      {
        assertion = (entry.value.owner or null) == null || hasAttr entry.value.owner config.users.users;
        message = "secret-service: secret ${entry.name} references unknown owner '${entry.value.owner or ""}'";
      }
      {
        assertion = (entry.value.group or null) == null || hasAttr entry.value.group config.users.groups;
        message = "secret-service: secret ${entry.name} references unknown group '${entry.value.group or ""}'";
      }
    ]
  ) (attrValues effectiveSecrets);

  mkTemplate =
    scope: templateName: template:
    let
      name =
        if scope == "machine" then
          "${clusterName}/${machineName}/${templateName}"
        else
          "${clusterName}/${templateName}";
      content =
        if isFunction template.content then
          let
            args = builtins.functionArgs template.content;
          in
          template.content (
            { inherit config; }
            // optionalAttrs (args ? lib) { inherit lib; }
            // optionalAttrs (args ? pkgs) { inherit pkgs; }
          )
        else
          template.content;
    in
    {
      inherit name;
      value =
        {
          inherit (template) path mode restartUnits reloadUnits;
          inherit content;
        }
        // optionalAttrs (template.owner != null) { owner = template.owner; }
        // optionalAttrs (template.group != null) { group = template.group; };
    };

  templates = builtins.listToAttrs (
    map (entry: {
      inherit (entry) name value;
    }) (
      concatMap (
        templateName:
        let
          template = clusterTemplates.${templateName};
        in
        if
          template.sopsFile == null
          || secretLib.clusterSecretVisibleToMachine {
            inherit service machineName;
            secret = { inherit (template) sopsFile; };
          }
        then
          [ (mkTemplate "cluster" templateName template) ]
        else
          [ ]
      ) (attrNames clusterTemplates)
      ++ concatMap (
        templateName: [ (mkTemplate "machine" templateName machineTemplates.${templateName}) ]
      ) (attrNames machineTemplates)
    )
  );

  keySource = machine.deployment.secrets.keySource;
  hasManagedAgeKey = keySource.type == "age" || keySource.type == "keepass";
  templatePlaceholderTokens = builtins.concatMap (
    template:
    map builtins.head (
      builtins.filter builtins.isList (
        builtins.split "(<SOPS:[0-9a-f]+:PLACEHOLDER>)" template.content
      )
    )
  ) (builtins.attrValues templates);
  knownPlaceholders = builtins.attrValues config.sops.placeholder;
  unknownTemplatePlaceholders = builtins.filter (
    token: !(builtins.elem token knownPlaceholders)
  ) templatePlaceholderTokens;

  keyPreflight = ''
    if [ ! -s ${escapeShellArg keySource.targetKeyFile} ]; then
      echo "ERROR: sops age key is missing at ${keySource.targetKeyFile}" >&2
      echo "" >&2
      echo "Install it first:" >&2
      echo "  nix run .#${clusterName}.${machineName}.secretsInstallKey" >&2
      echo "" >&2
      echo "Then deploy again." >&2
      exit 1
    fi
  '';

  assertions = [
    {
      assertion = duplicateKeys == [ ];
      message = "secret-service: duplicate (sopsFile, key) mappings: ${concatStringsSep ", " duplicateKeys}";
    }
    {
      assertion = keySource.type != "age" || keySource.age.sourceKeyFile != null;
      message = "secret-service: machines.${machineName}.deployment.secrets.keySource.age.sourceKeyFile is required for type = \"age\"";
    }
    {
      assertion = keySource.type != "keepass" || keySource.keepass.databasePath != null;
      message = "secret-service: machines.${machineName}.deployment.secrets.keySource.keepass.databasePath is required for type = \"keepass\"";
    }
    {
      assertion =
        keySource.type != "keepass"
        || !(keySource.keepass.passwordFile != null && keySource.keepass.passwordCommand != null);
      message = "secret-service: machines.${machineName}.deployment.secrets.keySource.keepass.passwordFile and .passwordCommand are mutually exclusive";
    }
    {
      assertion = unknownTemplatePlaceholders == [ ];
      message = "secret-service: templates on ${machineName} reference unknown placeholders: ${concatStringsSep ", " unknownTemplatePlaceholders}";
    }
    {
      assertion = formatConflicts == [ ];
      message = "secret-service: sops files with conflicting secret formats on ${machineName}: ${concatStringsSep ", " formatConflicts}";
    }
  ]
  ++ ownerGroupAssertions
  ++ concatMap (
    user:
    mapAttrsToList (
      secretName: secret:
      let
        entry = mkSecret "machine" user secretName secret;
      in
      {
        assertion = !(entry.value.neededForUsers && (secret.owner != null || secret.group != null));
        message = "secret-service: machines.${machineName}.secrets.${user}.${secretName} sets neededForUsers with owner/group; sops-nix requires root ownership for these secrets";
      }
    ) machineSecrets.${user}
  ) (attrNames machineSecrets)
  ++ concatMap (
    user:
    mapAttrsToList (
      secretName: secret:
      let
        entry = mkSecret "cluster" user secretName secret;
      in
      {
        assertion = !(entry.value.neededForUsers && (secret.owner != null || secret.group != null));
        message = "secret-service: services.secrets.secrets.${user}.${secretName} sets neededForUsers with owner/group; sops-nix requires root ownership for these secrets";
      }
    ) clusterSecrets.${user}
  ) (attrNames clusterSecrets);
in
{
  config =
    let
      projected = lib.mkMerge [
      {
        sops.secrets = effectiveSecrets;
        sops.templates = templates;
      }

      (mkIf (service.keepGenerations != null) {
        sops.keepGenerations = mkDefault service.keepGenerations;
      })
      (mkIf (service.useTmpfs != null) {
        sops.useTmpfs = mkDefault service.useTmpfs;
      })
      (mkIf (service.log != null) {
        sops.log = mkDefault service.log;
      })
      (mkIf (service.validateSopsFiles != null) {
        sops.validateSopsFiles = mkDefault service.validateSopsFiles;
      })
      (mkIf (service.useSystemdActivation != null) {
        sops.useSystemdActivation = mkDefault service.useSystemdActivation;
      })
      (mkIf (service.environment != { }) {
        sops.environment = service.environment;
      })

      (mkIf hasManagedAgeKey {
        sops.age.keyFile = keySource.targetKeyFile;
        system.activationScripts.setupSecrets.text = mkBefore keyPreflight;
      })
      (mkIf (hasManagedAgeKey && config.sops.useSystemdActivation && config.sops.secrets != { }) {
        systemd.services.sops-install-secrets.preStart = mkBefore keyPreflight;
      })
      (mkIf (keySource.type == "ssh") {
        sops.age.sshKeyPaths = keySource.ssh.keyPaths;
      })

      { inherit assertions; }
      ];
    in
    if shadowed == [ ] then
      projected
    else
      lib.warn "secret-service: machine-scoped secrets shadow cluster-scoped secrets: ${concatStringsSep ", " shadowed}" projected;

}
