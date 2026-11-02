{
  lib,
  pkgs,
  secretLib,
}:

let
  inherit (builtins)
    attrNames
    concatMap
    filter
    ;

  inherit (lib)
    concatStringsSep
    escapeShellArg
    mapAttrsToList
    optionalString
    unique
    ;

  sops = "${pkgs.sops}/bin/sops";
  ssh = "${pkgs.openssh}/bin/ssh";
  ageKeygen = "${pkgs.age}/bin/age-keygen";
  jq = "${pkgs.jq}/bin/jq";
  sed = "${pkgs.gnused}/bin/sed";
  keepassxc = "${pkgs.keepassxc}/bin/keepassxc-cli";

  shellList = values: concatStringsSep " " (map escapeShellArg values);

  secretEntries =
    {
      service,
      clusterName,
      machine,
      machineName,
    }:
    let
      clusterSecrets = service.secrets or { };
      machineSecrets = builtins.removeAttrs (machine.secrets or { }) [ "templates" ];
      mk = scope: user: secretName: secret: {
        sopsFile = secretLib.secretSopsFileCommand {
          inherit
            service
            clusterName
            scope
            secret
            ;
          machineName = if scope == "machine" then machineName else null;
        };
        key = if secret.key != null then secret.key else "${user}/${secretName}";
        format = secret.format;
      };
    in
    concatMap (
      user:
      mapAttrsToList (secretName: secret: mk "cluster" user secretName secret) clusterSecrets.${user}
    ) (attrNames clusterSecrets)
    ++ concatMap (
      user:
      mapAttrsToList (secretName: secret: mk "machine" user secretName secret) machineSecrets.${user}
    ) (attrNames machineSecrets);

  uniqueFiles = entries: unique (map (entry: entry.sopsFile) entries);

  sshTargetOf =
    machine:
    let
      user = machine.deployment.targetUser or "root";
      host = machine.deployment.targetHost;
    in
    "${if user == null || user == "" then "root" else user}@${host}";

  sshArgsOf =
    machine:
    let
      port = machine.deployment.targetPort or null;
    in
    "-o BatchMode=yes -o StrictHostKeyChecking=accept-new"
    + optionalString (port != null) " -p ${toString port}";

  mkCheckBody =
    {
      service,
      clusterName,
      machine,
      machineName,
    }:
    let
      entries = secretEntries {
        inherit
          service
          clusterName
          machine
          machineName
          ;
      };
      files = uniqueFiles entries;
      keySource = machine.deployment.secrets.keySource;
      targetHost = machine.deployment.targetHost;
      target = sshTargetOf machine;
      sshArgs = sshArgsOf machine;
      targetKeyFile = escapeShellArg keySource.targetKeyFile;
      expectedKeyCommand = secretLib.keySourcePublicKeyCommand keySource;
      checkCommands = map (
        entry:
        secretLib.keyCheck {
          inherit sops;
          file = entry.sopsFile;
          key = entry.key;
          format = entry.format;
        }
      ) entries;
      keyEnv = secretLib.keySourceEnv keySource;
      sopsConfig = secretLib.sopsConfigFile service;
    in
    ''
      echo "Checking sops files for ${machineName}..."

      for file in ${shellList files}; do
        [ -f "$file" ] || {
          echo "ERROR: sops file does not exist: $file" >&2
          exit 1
        }
      done

      ${keyEnv}
      export SOPS_CONFIG=${escapeShellArg sopsConfig}

      if [ "${keySource.type}" = "age" ] || [ "${keySource.type}" = "keepass" ]; then
        if [ -n ${escapeShellArg targetHost} ]; then
          ${ssh} ${sshArgs} ${escapeShellArg target} "test -s ${targetKeyFile}" || {
            echo "ERROR: age key file is missing on ${machineName}: ${keySource.targetKeyFile}" >&2
            exit 1
          }
        elif [ ! -s ${targetKeyFile} ]; then
          echo "ERROR: age key file is missing: ${keySource.targetKeyFile}" >&2
          exit 1
        fi
      fi

      expected_key=""
      ${
        if expectedKeyCommand == "" then
          ""
        else
          ''
            expected_key="$(
              ${expectedKeyCommand}
            )"
          ''
      }

      if [ -z "$expected_key" ] && [ "${keySource.type}" != "native" ]; then
        echo "ERROR: could not derive the public key for ${machineName}" >&2
        exit 1
      fi

      if [ -n "$expected_key" ]; then
        if [ -n ${escapeShellArg targetHost} ]; then
          actual_key="$(${ssh} ${sshArgs} ${escapeShellArg target} "command -v age-keygen >/dev/null && age-keygen -y ${targetKeyFile}" 2>/dev/null || true)"
        elif [ -s ${targetKeyFile} ]; then
          actual_key="$(${ageKeygen} -y ${targetKeyFile} 2>/dev/null || true)"
        else
          actual_key=""
        fi
        if [ -n "$actual_key" ] && [ "$actual_key" != "$expected_key" ]; then
          echo "ERROR: age key does not match the configured source" >&2
          echo "  expected: $expected_key" >&2
          echo "  actual:   $actual_key" >&2
          exit 1
        fi

        for file in ${shellList files}; do
          ${pkgs.gnugrep}/bin/grep -qF "$expected_key" "$file" || {
            echo "ERROR: $file is not encrypted to the current machine key." >&2
            echo "  expected: $expected_key" >&2
            echo "" >&2
            echo "This usually means the key was rotated but sops files were not updated." >&2
            echo "Run:" >&2
            echo "  nix run .#${clusterName}.secrets.secretsSyncKeyHolders" >&2
            echo "" >&2
            echo "Then install the new target key:" >&2
            echo "  nix run .#${clusterName}.${machineName}.secretsInstallKey" >&2
            exit 1
          }
        done
      fi

      echo "Checking declared keys..."
      ${concatStringsSep "\n" checkCommands}

      echo "Secret check passed for ${machineName}."
    '';

  mkInstallKeyBody =
    machine:
    let
      keySource = machine.deployment.secrets.keySource;
      target = sshTargetOf machine;
      sshArgs = sshArgsOf machine;
      keyFile = escapeShellArg keySource.targetKeyFile;
      installFromStdin = "${ssh} ${sshArgs} ${escapeShellArg target} \"umask 077; mkdir -p \\\"$(dirname ${keyFile})\\\"; cat > ${keyFile}; chmod 600 ${keyFile}\"";
    in
    if keySource.type == "age" then
      ''
        echo "Installing age key from ${keySource.age.sourceKeyFile}..."
        test -s ${escapeShellArg (toString keySource.age.sourceKeyFile)} || {
          echo "ERROR: age source key is missing: ${keySource.age.sourceKeyFile}" >&2
          exit 1
        }
        ${installFromStdin} < ${escapeShellArg (toString keySource.age.sourceKeyFile)}
      ''
    else if keySource.type == "keepass" then
      ''
        echo "Extracting age key from KeePass entry ${keySource.keepass.entry}..."
        tmp_key="$(mktemp)"
        trap 'rm -f "$tmp_key"' EXIT
        ${secretLib.keepassExtractCommand keySource.keepass} > "$tmp_key"
        test -s "$tmp_key" || { echo "ERROR: KeePass entry did not yield an age key" >&2; exit 1; }
        ${installFromStdin} < "$tmp_key"
      ''
    else
      ''
        echo "Key source type '${keySource.type}' needs no key installation."
      '';

  mkInstallKeyScript =
    {
      clusterConfig,
      machineName,
    }:
    let
      machine = secretLib.machineOf clusterConfig;
      installBody = mkInstallKeyBody machine;
    in
    ''
      set -euo pipefail

      ${installBody}

      echo "Key installation/check complete for ${machineName}."
      echo "Deploy secret changes through the normal system deployment."
    '';

  mkRemoveOldScript =
    {
      clusterConfig,
      machineName,
    }:
    let
      machine = secretLib.machineOf clusterConfig;
      keySource = machine.deployment.secrets.keySource;
      installBody = mkInstallKeyBody machine;
    in
    ''
      set -euo pipefail

      if [ "${keySource.type}" = "age" ] || [ "${keySource.type}" = "keepass" ]; then
        # Installing the current key replaces all previous identities.
        ${installBody}
        echo "Old identities removed from ${machineName}."
        exit 0
      fi

      echo "Key source type '${keySource.type}' has no old identities managed by this service."
    '';

  mkSecretsKeyGenerateScript =
    {
      clusterConfig,
      machineName,
    }:
    let
      machine = secretLib.machineOf clusterConfig;
      clusterName = secretLib.clusterNameOf clusterConfig;
      keySource = machine.deployment.secrets.keySource;
      keepass = keySource.keepass;
      keyFileArg = secretLib.keepassKeyFileArg keepass;
      passwordCommand = secretLib.keepassPasswordCommand keepass;
      passwordSetup = optionalString (passwordCommand != "") ''
        password="$(${passwordCommand})"
      '';
      keepassExtract = secretLib.keepassExtractCommand keepass;
      keepassDb = escapeShellArg (if keepass.databasePath == null then "" else toString keepass.databasePath);
      keepassEntryValue =
        if keepass.entry != null
        then keepass.entry
        else "clusterConfig/${clusterName}/machines/${machineName}";
      keepassEntry = escapeShellArg keepassEntryValue;
      publicCommand = secretLib.keySourcePublicKeyCommand keySource;
    in
    ''
      set -euo pipefail

      force=0
      if [ "${"$"}{1:-}" = "--force" ]; then
        force=1
      fi

      case "${keySource.type}" in
        age)
          source=${escapeShellArg (if keySource.age.sourceKeyFile == null then "" else keySource.age.sourceKeyFile)}
          if [ -e "$source" ] && [ "$force" -ne 1 ]; then
            echo "ERROR: $source already exists; pass --force to overwrite it." >&2
            exit 1
          fi
          if [ -e "$source" ]; then
            echo "WARNING: overwriting existing age key: $source" >&2
          fi
          mkdir -p "$(dirname "$source")"
          tmp_key="$(mktemp)"
          trap 'rm -f "$tmp_key"' EXIT
          rm -f "$tmp_key"
          ${ageKeygen} -o "$tmp_key" >/dev/null 2>&1
          install -m 600 "$tmp_key" "$source"
          public_key="$(${ageKeygen} -y "$source")"
          printf 'Wrote age key: %s\nPublic key: %s\n' "$source" "$public_key"
          ;;
        keepass)
          tmp_key="$(mktemp)"
          trap 'rm -f "$tmp_key"' EXIT
          rm -f "$tmp_key"
          ${ageKeygen} -o "$tmp_key" >/dev/null 2>&1
          ${passwordSetup}
          entry_key="$(grep '^AGE-SECRET' "$tmp_key")"
          test -n "$entry_key" || { echo "ERROR: generated age key has no private identity line" >&2; exit 1; }
          if [ -n "${"$"}{password:-}" ]; then
            if ${keepassExtract} >/dev/null 2>&1; then
              printf '%s\n%s\n' "$password" "$entry_key" | ${keepassxc} edit -q -p ${keyFileArg} ${keepassDb} ${keepassEntry}
              echo "WARNING: overwrote existing KeePass entry: ${keepassEntryValue}" >&2
            else
              printf '%s\n%s\n' "$password" "$entry_key" | ${keepassxc} add -q -p ${keyFileArg} ${keepassDb} ${keepassEntry}
            fi
          else
            if ${keepassExtract} >/dev/null 2>&1; then
              ${keepassxc} edit -q -p ${keyFileArg} ${keepassDb} ${keepassEntry}
              echo "WARNING: overwrote existing KeePass entry: ${keepassEntryValue}" >&2
            else
              ${keepassxc} add -q -p ${keyFileArg} ${keepassDb} ${keepassEntry}
            fi
          fi
          public_key="$(
            ${publicCommand}
          )"
          printf 'Wrote KeePass entry: %s\nPublic key: %s\n' ${keepassEntry} "$public_key"
          ;;
        ssh)
          public_key="$(
            ${publicCommand}
          )"
          printf 'SSH key sources are verify-only. Public key: %s\n' "$public_key"
          ;;
        native)
          echo "ERROR: native key sources are not generated by this service." >&2
          exit 1
          ;;
      esac

      case "${keySource.type}" in
        age|keepass)
          echo ""
          echo "Next:"
          echo "  nix run .#${clusterName}.secrets.secretsSyncKeyHolders"
          echo "  nix run .#${clusterName}.${machineName}.secretsInstallKey"
          ;;
      esac
    '';

  mkSecretEditScript =
    {
      clusterConfig,
      machineName ? null,
      scope,
      group ? null,
    }:
    let
      service = secretLib.serviceOf clusterConfig;
      clusterName = secretLib.clusterNameOf clusterConfig;
      file = secretLib.resolveSopsFileCommand {
        inherit
          service
          clusterName
          scope
          ;
        machineName = if scope == "machine" then machineName else null;
        value = if group == null then null else "cluster/${group}";
      };
      sopsConfig = secretLib.sopsConfigFile service;
      keyEnv = secretLib.keySourceEnv (
        if scope == "machine" then
          (secretLib.machineOf clusterConfig).deployment.secrets.keySource
        else
          service.adminKeySource
      );
    in
    ''
      set -euo pipefail
      export SOPS_CONFIG=${escapeShellArg sopsConfig}
      ${keyEnv}
      ${sops} edit ${escapeShellArg file} "$@"
    '';

  mkSecretSetScript =
    {
      clusterConfig,
      machineName ? null,
      scope,
      group ? null,
    }:
    let
      service = secretLib.serviceOf clusterConfig;
      clusterName = secretLib.clusterNameOf clusterConfig;
      defaultFile = secretLib.resolveSopsFileCommand {
        inherit
          service
          clusterName
          scope
          ;
        machineName = if scope == "machine" then machineName else null;
        value = if group == null then null else "cluster/${group}";
      };
      entries = secretEntries {
        inherit
          service
          clusterName
          ;
        machine = if scope == "machine" then secretLib.machineOf clusterConfig else { secrets = { }; };
        machineName = if scope == "machine" then machineName else "";
      };
      fileCase = concatStringsSep "\n" (
        map (entry: "    ${escapeShellArg entry.key}) file=${escapeShellArg entry.sopsFile} ;;") (
          if group == null then entries else filter (entry: entry.sopsFile == defaultFile) entries
        )
      );
      sopsConfig = secretLib.sopsConfigFile service;
      keyEnv = secretLib.keySourceEnv (
        if scope == "machine" then
          (secretLib.machineOf clusterConfig).deployment.secrets.keySource
        else
          service.adminKeySource
      );
    in
    ''
            set -euo pipefail
            export SOPS_CONFIG=${escapeShellArg sopsConfig}
            ${keyEnv}
            key=""
            if [ "${"$"}{1:-}" = "--key" ]; then
              shift
              key="${"$"}{1:-}"
            else
              key="${"$"}{1:-}"
            fi
            if [ -z "$key" ]; then
              echo "Usage: secretSet --key <user>/<secret> < value" >&2
              exit 1
            fi
            file=${escapeShellArg defaultFile}
            case "$key" in
      ${fileCase}
            esac
            key_path=$(printf '%s' "$key" | ${sed} 's#/#"]["#g')
            key_path="[\"$key_path\"]"
            value_json="$(cat | ${jq} -Rs .)"
            printf '%s' "$value_json" | ${sops} set --value-stdin "$file" "$key_path"
    '';

  mkSyncKeyHoldersScript =
    { clusterConfig }:
    let
      service = secretLib.serviceOf clusterConfig;
      clusterName = secretLib.clusterNameOf clusterConfig;
      sopsRoot = secretLib.sopsRootCommand service;
      sopsConfig = secretLib.sopsConfigFile service;
      relativeRoot = baseNameOf sopsRoot;
      selected = secretLib.selectedNodes service;
      nodeCommand = nodeName: {
        name = nodeName;
        command = secretLib.keySourcePublicKeyCommand (
          secretLib.keySourceOf (secretLib.nodeByName clusterConfig nodeName)
        );
      };
      nodeCommands = map nodeCommand selected;
      adminCommand =
        if service.adminKeySource == null then
          ""
        else
          secretLib.keySourcePublicKeyCommand service.adminKeySource;
      publicKeyCase = concatStringsSep "\n" (
        [ ''
          "admin") key="$(
            ${adminCommand}
          )" ;;
        '' ]
        ++ map (
          node:
          ''
            ${escapeShellArg node.name}) key="$(
              ${node.command}
            )" ;;
          ''
        ) nodeCommands
      );
      machineRules = map (
        nodeName:
        let
          regex = "^${relativeRoot}/${clusterName}/${service.machinesSubDir}/${nodeName}\\.yaml$";
        in
        "append_rule ${escapeShellArg regex} ${escapeShellArg nodeName}"
      ) selected;
      groupRules = map (
        group:
        let
          members = service.groups.${group} or [ ];
          regex = "^${relativeRoot}/${clusterName}/${service.clusterSubDir}/${group}\\.yaml$";
        in
        "append_rule ${escapeShellArg regex} ${shellList members}"
      ) (attrNames (service.groups or { }));
      clusterRegex = "^${relativeRoot}/${clusterName}/cluster\\.yaml$";
      clusterRule = "append_rule ${escapeShellArg clusterRegex} ${shellList selected}";
      adminKeyEnv = secretLib.keySourceEnv service.adminKeySource;
    in
    ''
      set -euo pipefail
      sopsConfig=${escapeShellArg sopsConfig}
      public_key_cache="$(mktemp -d)"
      trap 'rm -rf "$public_key_cache"' EXIT

      public_key_for() {
        local name="$1"
        local cache="$public_key_cache/$name"
        if [ -f "$cache" ]; then
          cat "$cache"
          return 0
        fi
        local key=""
        case "$name" in
      ${publicKeyCase}
          *)
            echo "ERROR: no public key available for '$name'. Configure its key source or native.publicKey." >&2
            return 1
            ;;
        esac
        if [ -z "$key" ]; then
          echo "ERROR: no public key available for '$name'. Configure its key source or native.publicKey." >&2
          return 1
        fi
        printf '%s\n' "$key" > "$cache"
        printf '%s\n' "$key"
      }

      append_rule() {
        local regex="$1"
        shift
        printf '  - path_regex: %s\n' "$regex" >> "$sopsConfig"
        printf '    key_groups:\n' >> "$sopsConfig"
        printf '      - age:\n' >> "$sopsConfig"
        local used=" "
        local name key
        for name in admin "$@"; do
          case "$used" in
            *" $name "*) continue ;;
          esac
          used="$used$name "
          key="$(public_key_for "$name")" || return 1
          if [ -z "$key" ]; then
            echo "ERROR: key source for '$name' did not produce a public key." >&2
            return 1
          fi
          printf '          - %s\n' "$key" >> "$sopsConfig"
        done
      }

      mkdir -p ${escapeShellArg (dirOf sopsConfig)}
      : > ${escapeShellArg sopsConfig}
      printf 'creation_rules:\n' >> ${escapeShellArg sopsConfig}

      ${concatStringsSep "\n" (machineRules ++ groupRules ++ [ clusterRule ])}

      echo "Wrote ${sopsConfig}"
      export SOPS_CONFIG=${escapeShellArg sopsConfig}
      ${adminKeyEnv}
      if [ -z "${"$"}{SOPS_AGE_KEY_FILE:-}" ] && [ -z "${"$"}{SOPS_AGE_SSH_PRIVATE_KEY_FILE:-}" ]; then
        echo "ERROR: configure services.secrets.adminKeySource, or export SOPS_AGE_KEY_FILE/SOPS_AGE_SSH_PRIVATE_KEY_FILE." >&2
        exit 1
      fi

      echo "Updating file keys..."
      while IFS= read -r -d "" file; do
        echo "  $file"
        ${sops} updatekeys --yes "$file"
      done < <(find ${escapeShellArg "${sopsRoot}/${clusterName}"} -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o -name '*.env' -o -name '*.ini' \) -print0)

      echo "Rotating data keys..."
      while IFS= read -r -d "" file; do
        ${sops} rotate --in-place "$file"
      done < <(find ${escapeShellArg "${sopsRoot}/${clusterName}"} -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o -name '*.env' -o -name '*.ini' \) -print0)

      echo "Key-holder files updated. Review the changed sops files and .sops.yaml."
    '';

  mkUpdateKeysScript =
    {
      clusterConfig,
      rotate ? false,
      group ? null,
    }:
    let
      service = secretLib.serviceOf clusterConfig;
      clusterName = secretLib.clusterNameOf clusterConfig;
      sopsRoot = secretLib.sopsRootCommand service;
      sopsConfig = secretLib.sopsConfigFile service;
      adminKeyEnv = secretLib.keySourceEnv service.adminKeySource;
      command = if rotate then "rotate --in-place" else "updatekeys --yes";
      groupFile = secretLib.resolveSopsFileCommand {
        inherit
          service
          clusterName
          ;
        scope = "cluster";
        value = if group == null then null else "cluster/${group}";
      };
    in
    ''
      set -euo pipefail
      export SOPS_CONFIG=${escapeShellArg sopsConfig}
      ${adminKeyEnv}
      if [ -z "${"$"}{SOPS_AGE_KEY_FILE:-}${"$"}{SOPS_AGE_SSH_PRIVATE_KEY_FILE:-}" ]; then
        echo "ERROR: configure services.secrets.adminKeySource, or export SOPS_AGE_KEY_FILE/SOPS_AGE_SSH_PRIVATE_KEY_FILE." >&2
        exit 1
      fi
      ${
        if group == null then
          ''
            while IFS= read -r -d "" file; do
              echo "  $file"
              ${sops} ${command} "$file"
            done < <(find ${escapeShellArg "${sopsRoot}/${clusterName}"} -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o -name '*.env' -o -name '*.ini' \) -print0)
          ''
        else
          ''
            ${sops} ${command} ${escapeShellArg groupFile}
          ''
      }
    '';

  mkCheckScript =
    { clusterConfig, machineName }:
    let
      service = secretLib.serviceOf clusterConfig;
      clusterName = secretLib.clusterNameOf clusterConfig;
      machine = secretLib.machineOf clusterConfig;
    in
    pkgs.writeShellScriptBin "secretsCheck" (mkCheckBody {
      inherit
        service
        clusterName
        machine
        machineName
        ;
    });

in
{
  inherit
    mkCheckScript
    mkRemoveOldScript
    mkSecretEditScript
    mkSecretsKeyGenerateScript
    mkSecretSetScript
    mkSyncKeyHoldersScript
    mkUpdateKeysScript
    mkInstallKeyScript
    ;
}
