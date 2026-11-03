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
  yq = "${pkgs.yq-go}/bin/yq";
  keepassxc = "${pkgs.keepassxc}/bin/keepassxc-cli";
  git = "${pkgs.git}/bin/git";
  realpath = "${pkgs.coreutils}/bin/realpath";

  shellList = values: concatStringsSep " " (map escapeShellArg values);

  sopsRootResolve =
    service:
    let
      spec = secretLib.sopsRootSpec service;
      osPath = if spec.osPath == null then "" else spec.osPath;
    in
    ''
      sops_root_store=${escapeShellArg spec.nixPath}
      sops_root_os=${escapeShellArg osPath}
      export PATH="${pkgs.coreutils}/bin:${pkgs.git}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:$PATH"

      # Find the nearest enclosing flake without requiring Git. This is enough
      # for explicit osPath configurations, which may be used outside a repo.
      find_flake_root() {
        flake_root="$PWD"
        while [ "$flake_root" != "/" ] && [ ! -f "$flake_root/flake.nix" ]; do
          flake_root="$(dirname "$flake_root")"
        done
        if [ ! -f "$flake_root/flake.nix" ]; then
          flake_root=""
        fi
      }

      find_git_root() {
        repo_root="$(${git} -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || return 1
      }

      # Only expand the forms documented in sopsRoot.osPath. Do not use eval:
      # it would execute arbitrary shell text from the configuration.
      expand_os_path() {
        local expanded="$1"
        case "$expanded" in
          "~") expanded="$HOME" ;;
          "~/"*) expanded="$HOME/''${expanded:2}" ;;
          '$HOME'|'$HOME/'*) expanded="$HOME''${expanded:5}" ;;
        esac
        printf '%s' "$expanded"
      }

      resolve_sops_root() {
        find_flake_root
        if [ -n "$sops_root_os" ]; then
          expanded="$(expand_os_path "$sops_root_os")"
          case "$expanded" in
            /*) sops_root="$expanded" ;;
            *)
              if [ -n "$flake_root" ]; then
                sops_root="$flake_root/$expanded"
              else
                sops_root="$PWD/$expanded"
              fi
              ;;
          esac
          sops_root="$(${realpath} -m -- "$sops_root")"
        else
          if ! find_git_root; then
            echo "ERROR: cannot determine the Git repository root for the sops root." >&2
            echo "Run this helper from inside the flake, or configure sopsRoot.osPath." >&2
            exit 1
          fi
          if [ -z "$flake_root" ]; then
            echo "ERROR: cannot find an enclosing flake.nix." >&2
            echo "Run this helper from inside the flake, or configure sopsRoot.osPath." >&2
            exit 1
          fi
          case "$flake_root" in
            "$repo_root"|"$repo_root"/*) ;;
            *)
              echo "ERROR: the enclosing flake is outside the current Git repository." >&2
              exit 1
              ;;
          esac
          if [ "$flake_root" = "$repo_root" ]; then
            flake_prefix=""
          else
            flake_prefix="''${flake_root#"$repo_root"/}/"
          fi
          case "$sops_root_store" in
            /nix/store/*)
              sops_root_rel="''${sops_root_store#/nix/store/*/}"
              case "$sops_root_rel" in
                "$flake_prefix"*) sops_root_rel="''${sops_root_rel#"$flake_prefix"}" ;;
              esac
              sops_root="$sops_root_rel"
              ;;
            *) sops_root="$sops_root_store" ;;
          esac
        fi
        if [ -n "$flake_root" ]; then
          cd "$flake_root"
        fi
        sops_config="$sops_root/.sops.yaml"
      }

      resolve_sops_root

      sops_path() {
        case "$1" in
          /*) printf '%s' "$1" ;;
          *) printf '%s/%s' "$sops_root" "$1" ;;
        esac
      }
    '';

  sopsRootPreamble =
    { service, clusterName }:
    let
      clusterArg = escapeShellArg clusterName;
    in
    sopsRootResolve service
    + ''
      marker="$sops_root/.secret-service-root"
      if [ ! -f "$sops_root_store/.secret-service-root" ]; then
        echo "ERROR: missing secret-service root marker in the evaluated sops root:" >&2
        echo "  $sops_root_store/.secret-service-root" >&2
        echo "" >&2
        echo "Run the root initializer first:" >&2
        echo "  nix run .#${clusterName}.secrets.secretsInitRoot" >&2
        exit 1
      fi
      if [ ! -f "$marker" ]; then
        echo "ERROR: missing secret-service root marker in the working tree:" >&2
        echo "  $marker" >&2
        echo "" >&2
        echo "Commit the marker and re-run Nix so the evaluated sops root contains it." >&2
        exit 1
      fi
      marker_schema="$(${yq} -r '.schema // ""' "$marker" 2>/dev/null || true)"
      marker_root_id="$(${yq} -r '.rootId // ""' "$marker" 2>/dev/null || true)"
      marker_clusters="$(${yq} -r '.clusters[]?' "$marker" 2>/dev/null || true)"
      if [ "$marker_schema" != "1" ] || [ -z "$marker_root_id" ]; then
        echo "ERROR: malformed secret-service root marker: $marker" >&2
        echo "Expected schema 1 and a non-empty rootId." >&2
        exit 1
      fi
      if ! printf '%s\n' "$marker_clusters" | grep -qxF ${clusterArg}; then
        echo "ERROR: secret-service root marker does not list cluster '${clusterName}'." >&2
        echo "  marker: $marker" >&2
        exit 1
      fi
      if ! cmp -s "$sops_root_store/.secret-service-root" "$marker"; then
        echo "ERROR: secret-service root marker mismatch." >&2
        echo "  evaluated: $sops_root_store/.secret-service-root" >&2
        echo "  working:   $marker" >&2
        echo "" >&2
        echo "Run this helper from inside the flake, commit the marker, or configure:" >&2
        echo "  sopsRoot = { nixPath = ./secrets; osPath = 'secrets'; };" >&2
        exit 1
      fi
    '';

  sopsRootPreambleOptional =
    { service, clusterName }:
    sopsRootResolve service
    + ''
      if [ ! -f "$sops_root_store/.secret-service-root" ] || [ ! -f "$sops_root/.secret-service-root" ]; then
        echo "WARNING: secret-service root marker is missing; run:" >&2
        echo "  nix run .#${clusterName}.secrets.secretsInitRoot" >&2
      fi
    '';

  keySourceManagedInSync =
    keySource:
    keySource.type != "native"
    || keySource.native.publicKey != null
    || keySource.native.publicKeyFile != null;

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
      map (
        secretName:
        mk "cluster" user secretName clusterSecrets.${user}.${secretName}
      ) (
        filter (
          secretName:
          secretLib.clusterSecretVisibleToMachine {
            inherit service machineName;
            secret = clusterSecrets.${user}.${secretName};
          }
        ) (attrNames clusterSecrets.${user})
      )
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
      clusterConfig,
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
          fileShell = "$(sops_path ${escapeShellArg entry.sopsFile})";
          key = entry.key;
          format = entry.format;
        }
      ) entries;
      keyEnv = secretLib.keySourceEnv keySource;
      selected = secretLib.selectedNodes service;
      fileRecipients = managedFileRecipients {
        inherit service clusterName clusterConfig;
      };
      nodeCommand = nodeName: {
        name = nodeName;
        command = secretLib.keySourcePublicKeyCommand (
          secretLib.keySourceOf (secretLib.nodeByName clusterConfig nodeName)
        );
      };
      nodeCommands = map nodeCommand selected;
      adminCommand = secretLib.keySourcePublicKeyCommand service.adminKeySource;
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
      expectedRecipientNames = file: [ "admin" ] ++ (fileRecipients.${file} or [ ]);
      recipientCases = concatStringsSep "\n" (
        map (
          file:
          "${escapeShellArg file}) expected_names=(${shellList (expectedRecipientNames file)}) ;;"
        ) files
      );
    in
    ''
      set -euo pipefail
      ${sopsRootPreambleOptional { inherit service clusterName; }}
      echo "Checking sops files for ${machineName}..."

      for file in ${shellList files}; do
        sops_file="$(sops_path "$file")"
        [ -f "$sops_file" ] || {
          echo "ERROR: sops file does not exist: $sops_file" >&2
          exit 1
        }
      done

      ${keyEnv}
      export SOPS_CONFIG="$sops_config"

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
        target_key_tmp="$(mktemp)"
        trap 'rm -f "$target_key_tmp" "''${__secret_service_key_file:-}"' EXIT
        if [ -n ${escapeShellArg targetHost} ]; then
          ${ssh} ${sshArgs} ${escapeShellArg target} "cat -- ${targetKeyFile}" > "$target_key_tmp" || {
            echo "ERROR: could not read age key file on ${machineName}: ${keySource.targetKeyFile}" >&2
            exit 1
          }
          actual_key="$(${ageKeygen} -y "$target_key_tmp" 2>/dev/null || true)"
        elif [ -s ${targetKeyFile} ]; then
          actual_key="$(${ageKeygen} -y ${targetKeyFile} 2>/dev/null || true)"
        else
          actual_key=""
        fi
        if [ -z "$actual_key" ] || [ "$actual_key" != "$expected_key" ]; then
          echo "ERROR: target age key does not match the configured source" >&2
          echo "  expected: $expected_key" >&2
          echo "  actual:   $actual_key" >&2
          echo "" >&2
          echo "Install the expected key with:" >&2
          echo "  nix run .#${clusterName}.${machineName}.secretsInstallKey" >&2
          exit 1
        fi

        for file in ${shellList files}; do
          sops_file="$(sops_path "$file")"
          ${pkgs.gnugrep}/bin/grep -qF "$expected_key" "$sops_file" || {
            echo "ERROR: $sops_file is not encrypted to the current machine key." >&2
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

      public_key_for() {
        local name="$1"
        local key=""
        case "$name" in
      ${publicKeyCase}
          *)
            echo "ERROR: no public key available for '$name'" >&2
            return 1
            ;;
        esac
        if [ -z "$key" ]; then
          echo "ERROR: no public key available for '$name'" >&2
          return 1
        fi
        printf '%s\n' "$key"
      }

      echo "Checking recipients..."
      for file in ${shellList files}; do
        sops_file="$(sops_path "$file")"
        case "$file" in
          *.yaml|*.yml|*.json)
            expected_names=()
            case "$file" in
      ${recipientCases}
            esac
            expected_recipients=""
            for name in "''${expected_names[@]}"; do
              expected_recipients="$expected_recipients$(public_key_for "$name")"$'\n'
            done
            expected_recipients="$(printf '%s' "$expected_recipients" | sort -u)"
            actual_recipients="$(${yq} -r '.sops.age[]?.recipient' "$sops_file" 2>/dev/null | sort -u)"
            if [ "$actual_recipients" != "$expected_recipients" ]; then
              echo "ERROR: unexpected recipient set in $sops_file" >&2
              echo "  expected:" >&2
              printf '%s\n' "$expected_recipients" | sed 's/^/    /' >&2
              echo "  actual:" >&2
              printf '%s\n' "$actual_recipients" | sed 's/^/    /' >&2
              echo "Run:" >&2
              echo "  nix run .#${clusterName}.secrets.secretsSyncKeyHolders" >&2
              exit 1
            fi
            ;;
          *)
            echo "WARNING: skipping recipient check for non-structured sops file: $file" >&2
            ;;
        esac
      done

      echo "Checking declared keys..."
      ${concatStringsSep "\n" checkCommands}

      echo "Secret check passed for ${machineName}."
    '';

  mkInstallKeyBody =
    {
      machine,
      clusterName,
      machineName,
    }:
    let
      keySource = machine.deployment.secrets.keySource;
      keepassEntry = secretLib.keepassEntry {
        inherit clusterName machineName;
        keepass = keySource.keepass;
      };
      target = sshTargetOf machine;
      sshArgs = sshArgsOf machine;
      keyFile = escapeShellArg keySource.targetKeyFile;
      installFromStdin = "${ssh} ${sshArgs} ${escapeShellArg target} \"umask 077; mkdir -p \\\"$(dirname ${keyFile})\\\"; cat > ${keyFile}; chmod 600 ${keyFile}\"";
      verifyInstalledKey = ''
        expected_key="$(
          ${secretLib.keySourcePublicKeyCommand keySource}
        )"
        target_key_tmp="$(mktemp)"
        ${ssh} ${sshArgs} ${escapeShellArg target} "cat -- ${keyFile}" > "$target_key_tmp"
        actual_key="$(${ageKeygen} -y "$target_key_tmp" 2>/dev/null || true)"
        rm -f "$target_key_tmp"
        if [ -z "$actual_key" ] || [ "$actual_key" != "$expected_key" ]; then
          echo "ERROR: installed key does not match the configured source" >&2
          echo "  expected: $expected_key" >&2
          echo "  actual:   $actual_key" >&2
          exit 1
        fi
        echo "Verified installed key: $actual_key"
      '';
    in
    if keySource.type == "age" then
      ''
        echo "Installing age key from ${keySource.age.sourceKeyFile}..."
        test -s ${escapeShellArg (toString keySource.age.sourceKeyFile)} || {
          echo "ERROR: age source key is missing: ${keySource.age.sourceKeyFile}" >&2
          exit 1
        }
        ${installFromStdin} < ${escapeShellArg (toString keySource.age.sourceKeyFile)}
        ${verifyInstalledKey}
      ''
    else if keySource.type == "keepass" then
      ''
        echo "Extracting age key from KeePass entry ${keepassEntry}..."
        tmp_key="$(mktemp)"
        trap 'rm -f "$tmp_key"' EXIT
        ${secretLib.keepassExtractCommand (keySource.keepass // { entry = keepassEntry; })} > "$tmp_key"
        test -s "$tmp_key" || { echo "ERROR: KeePass entry did not yield an age key" >&2; exit 1; }
        ${installFromStdin} < "$tmp_key"
        ${verifyInstalledKey}
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
      clusterName = secretLib.clusterNameOf clusterConfig;
      service = secretLib.serviceOf clusterConfig;
      installBody = mkInstallKeyBody { inherit machine clusterName machineName; };
    in
    ''
      set -euo pipefail
      ${sopsRootResolve service}

      ${installBody}

      echo "Key installation/check complete for ${machineName}."
      echo "Deploy secret changes through the normal system deployment."
    '';

  mkKeyGenerateScript =
    {
      clusterConfig,
      keySource,
      keyName,
      keepassEntryOverride ? null,
      nextCommands ? "",
    }:
    let
      clusterName = secretLib.clusterNameOf clusterConfig;
      service = secretLib.serviceOf clusterConfig;
      keepass = keySource.keepass;
      keyFileArg = secretLib.keepassKeyFileArg keepass;
      passwordCommand = secretLib.keepassPasswordCommand keepass;
      passwordSetup = optionalString (passwordCommand != "") ''
        password="$(${passwordCommand})"
      '';
      keepassExtract =
        if keySource.type == "keepass" then
          secretLib.keepassExtractCommand keepass
        else
          "";
      keepassDb = escapeShellArg (if keepass.databasePath == null then "" else toString keepass.databasePath);
      keepassEntryValue =
        if keepassEntryOverride != null then
          keepassEntryOverride
        else
          secretLib.keepassEntry {
            inherit clusterName keepass;
            machineName = keyName;
          };
      keepassEntry = escapeShellArg keepassEntryValue;
      publicCommand = secretLib.keySourcePublicKeyCommand keySource;
    in
    ''
      set -euo pipefail
      ${sopsRootResolve service}

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
          if [ "$force" -ne 1 ] && ${keepassExtract} >/dev/null 2>&1; then
            echo "ERROR: KeePass entry already exists: ${keepassEntryValue}; pass --force to overwrite it." >&2
            exit 1
          fi
          ensure_keepass_group() {
            local group="$1"
            local current=""
            local part
            IFS='/' read -ra parts <<< "$group"
            for part in "''${parts[@]}"; do
              [ -z "$part" ] && continue
              current="''${current:+$current/}$part"
              if [ -n "''${password:-}" ]; then
                if ! printf '%s\n' "$password" | ${keepassxc} ls -q ${keyFileArg} ${keepassDb} "$current" >/dev/null 2>&1; then
                  printf '%s\n' "$password" | ${keepassxc} mkdir -q ${keyFileArg} ${keepassDb} "$current"
                fi
              else
                if ! ${keepassxc} ls -q ${keyFileArg} ${keepassDb} "$current" >/dev/null 2>&1; then
                  ${keepassxc} mkdir -q ${keyFileArg} ${keepassDb} "$current"
                fi
              fi
            done
          }
          entry_group="$(dirname ${keepassEntry})"
          [ "$entry_group" != "." ] && ensure_keepass_group "$entry_group"
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

      ${nextCommands}
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
    in
    mkKeyGenerateScript {
      inherit clusterConfig keySource;
      keyName = machineName;
      nextCommands = optionalString (keySource.type == "age" || keySource.type == "keepass") ''
        echo ""
        echo "Next:"
        echo "  nix run .#${clusterName}.secrets.secretsSyncKeyHolders"
        echo "  nix run .#${clusterName}.${machineName}.secretsInstallKey"
      '';
    };

  mkAdminKeyGenerateScript =
    { clusterConfig }:
    let
      service = secretLib.serviceOf clusterConfig;
      clusterName = secretLib.clusterNameOf clusterConfig;
      keySource = service.adminKeySource;
      keepassEntry =
        if keySource.keepass.entry != null then
          keySource.keepass.entry
        else
          "clusterConfig/${clusterName}/admin";
    in
    mkKeyGenerateScript {
      inherit clusterConfig keySource;
      keyName = "admin";
      keepassEntryOverride = keepassEntry;
      nextCommands = optionalString (keySource.type == "age" || keySource.type == "keepass") ''
        echo ""
        echo "Next:"
        echo "  nix run .#${clusterName}.secrets.secretsSyncKeyHolders"
      '';
    };

  mkSecretsKeyGenerateAllScript =
    { clusterConfig }:
    let
      service = secretLib.serviceOf clusterConfig;
      clusterName = secretLib.clusterNameOf clusterConfig;
      adminTarget = {
        name = "admin";
        keySource = service.adminKeySource;
        keepassEntryOverride =
          if service.adminKeySource.keepass.entry != null then
            service.adminKeySource.keepass.entry
          else
            "clusterConfig/${clusterName}/admin";
      };
      machineTargets = map (
        name:
        let
          machine = secretLib.nodeByName clusterConfig name;
        in
        {
          inherit name;
          keySource = machine.deployment.secrets.keySource;
          keepassEntryOverride = null;
        }
      ) (secretLib.selectedNodes service);
      managedTargets = filter (
        target: target.keySource.type == "age" || target.keySource.type == "keepass"
      ) ([ adminTarget ] ++ machineTargets);
      commands = map (
        target:
        "${pkgs.writeShellScriptBin "secretsKeyGenerate-${target.name}" (
          mkKeyGenerateScript {
            inherit clusterConfig;
            inherit (target) keySource keepassEntryOverride;
            keyName = target.name;
          }
        )}/bin/secretsKeyGenerate-${target.name}"
      ) managedTargets;
    in
    ''
      set -euo pipefail
      ${optionalString (managedTargets == [ ]) ''
        echo "No managed age or KeePass key sources to generate."
      ''}
      for command in ${shellList commands}; do
        echo "=== $command ==="
        "$command" "$@"
      done
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
      keyEnv = secretLib.keySourceEnv (
        if scope == "machine" then
          (secretLib.machineOf clusterConfig).deployment.secrets.keySource
        else
          service.adminKeySource
      );
    in
    ''
      set -euo pipefail
      ${sopsRootPreamble { inherit service clusterName; }}
      export SOPS_CONFIG="$sops_config"
      ${keyEnv}
      ${sops} edit "$(sops_path ${escapeShellArg file})" "$@"
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
      keyEnv = secretLib.keySourceEnv (
        if scope == "machine" then
          (secretLib.machineOf clusterConfig).deployment.secrets.keySource
        else
          service.adminKeySource
      );
    in
    ''
            set -euo pipefail
            ${sopsRootPreamble { inherit service clusterName; }}
            export SOPS_CONFIG="$sops_config"
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
            key_path="$(printf '%s' "$key" | ${jq} -Rr 'split("/") | if any(. == "") then error("secret key contains an empty path segment") else map("[" + @json + "]") | join("") end')"
            sops_file="$(sops_path "$file")"
            if [ ! -s "$sops_file" ]; then
              mkdir -p "$(dirname "$sops_file")"
              printf '%s\n' '{}' | ${sops} --encrypt --filename-override "$sops_file" --output "$sops_file" /dev/stdin
            fi
            value_json="$(cat | ${jq} -Rs .)"
            printf '%s' "$value_json" | ${sops} set --value-stdin "$sops_file" "$key_path"
    '';

  mergeFileRecipients =
    entries:
    builtins.foldl' (
      acc: entry:
      if builtins.hasAttr entry.file acc then
        acc // { ${entry.file} = unique (acc.${entry.file} ++ entry.recipients); }
      else
        acc // { ${entry.file} = unique entry.recipients; }
    ) { } entries;

  managedFileRecipients =
    {
      service,
      clusterName,
      clusterConfig,
    }:
    let
      selected = secretLib.selectedNodes service;
      managedNode =
        nodeName:
        keySourceManagedInSync (
          secretLib.keySourceOf (secretLib.nodeByName clusterConfig nodeName)
        );
      managedSelected = filter managedNode selected;
      groups = attrNames (service.groups or { });
      machineFile = nodeName: {
        file = secretLib.resolveSopsFileCommand {
          inherit service clusterName;
          scope = "machine";
          machineName = nodeName;
        };
        recipients = [ nodeName ];
      };
      groupFile = group: {
        file = secretLib.resolveSopsFileCommand {
          inherit service clusterName;
          scope = "cluster";
          value = "cluster/${group}";
        };
        recipients = filter managedNode service.groups.${group};
      };
      clusterFile = {
        file = secretLib.resolveSopsFileCommand {
          inherit service clusterName;
          scope = "cluster";
        };
        recipients = managedSelected;
      };
      entriesForNode =
        nodeName:
        if !(managedNode nodeName) then
          [ ]
        else
          let
            machine = secretLib.nodeByName clusterConfig nodeName;
          in
          map (
            entry:
            {
              file = entry.sopsFile;
              recipients = [ nodeName ];
            }
          ) (secretEntries {
            inherit service clusterName;
            machineName = nodeName;
            machine = machine;
          });
    in
    mergeFileRecipients (
      [ clusterFile ]
      ++ map machineFile managedSelected
      ++ map groupFile groups
      ++ concatMap entriesForNode selected
    );

  mkSyncKeyHoldersScript =
    { clusterConfig }:
    let
      service = secretLib.serviceOf clusterConfig;
      clusterName = secretLib.clusterNameOf clusterConfig;
      selected = secretLib.selectedNodes service;
      managedSelected = filter (
        nodeName: keySourceManagedInSync (secretLib.keySourceOf (secretLib.nodeByName clusterConfig nodeName))
      ) selected;
      nativeSkipped = filter (
        nodeName: !(keySourceManagedInSync (secretLib.keySourceOf (secretLib.nodeByName clusterConfig nodeName)))
      ) selected;
      fileRecipients = managedFileRecipients {
        inherit service clusterName clusterConfig;
      };
      managedFiles = attrNames fileRecipients;
      nodeCommand = nodeName: {
        name = nodeName;
        command = secretLib.keySourcePublicKeyCommand (
          secretLib.keySourceOf (secretLib.nodeByName clusterConfig nodeName)
        );
      };
      nodeCommands = map nodeCommand managedSelected;
      adminCommand = secretLib.keySourcePublicKeyCommand service.adminKeySource;
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
      fileRules = map (
        file:
        "append_rule_file ${escapeShellArg file} ${shellList fileRecipients.${file}}"
      ) managedFiles;
      adminKeyEnv = secretLib.keySourceEnv service.adminKeySource;
    in
    ''
      set -euo pipefail
      ${sopsRootPreamble { inherit service clusterName; }}
      ${optionalString (nativeSkipped != [ ]) ''
        echo "WARNING: skipping unmanaged native key sources: ${concatStringsSep " " nativeSkipped}" >&2
      ''}
      public_key_cache="$(mktemp -d)"
      config_tmp="$(mktemp "$sops_config.XXXXXX")"
      backup_dir="$(mktemp -d)"
      backup_index="$backup_dir/index"
      : > "$backup_index"
      cleanup() {
        status=$?
        if [ "$status" -ne 0 ]; then
          while IFS=$'\t' read -r original backup; do
            [ -n "$original" ] && cp -a "$backup" "$original"
          done < "$backup_index"
        fi
        rm -rf "$public_key_cache" "$backup_dir"
        [ -e "$config_tmp" ] && rm -f "$config_tmp"
        [ -n "''${__secret_service_key_file:-}" ] && rm -f "$__secret_service_key_file"
        exit "$status"
      }
      trap cleanup EXIT

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

      regex_escape() {
        local input="$1"
        local output=""
        local char
        local i
        for ((i=0; i<''${#input}; i++)); do
          char="''${input:i:1}"
          case "$char" in
            '['|']'|'\'|'.'|'^'|'$'|'*'|'+'|'?'|'('|')'|'{'|'}'|'|') output="''${output}\\''${char}" ;;
            *) output="''${output}''${char}" ;;
          esac
        done
        printf '%s' "$output"
      }
      append_rule_file() {
        local file="$1"
        local regex
        shift
        # The sops configuration lives in sopsRoot, so sops matches path_regex
        # against paths relative to that directory.
        regex="$(regex_escape "$file")"
        append_rule "^$regex$" "$@"
      }

      append_rule() {
        local regex="$1"
        shift
        printf '  - path_regex: %s\n' "$regex" >> "$config_tmp"
        printf '    key_groups:\n' >> "$config_tmp"
        printf '      - age:\n' >> "$config_tmp"
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
          printf '          - %s\n' "$key" >> "$config_tmp"
        done
      }

      printf 'creation_rules:\n' >> "$config_tmp"
      ${concatStringsSep "\n" fileRules}

      if [ -f "$sops_config" ] && cmp -s "$config_tmp" "$sops_config"; then
        config_changed=0
      else
        config_changed=1
      fi

      export SOPS_CONFIG="$config_tmp"
      ${adminKeyEnv}
      trap cleanup EXIT
      if [ -z "${"$"}{SOPS_AGE_KEY_FILE:-}" ] && [ -z "${"$"}{SOPS_AGE_SSH_PRIVATE_KEY_FILE:-}" ]; then
        echo "ERROR: configure services.secrets.adminKeySource, or export SOPS_AGE_KEY_FILE/SOPS_AGE_SSH_PRIVATE_KEY_FILE." >&2
        exit 1
      fi

      backup_file() {
        local file="$1"
        local backup
        backup="$(mktemp "$backup_dir/file.XXXXXX")"
        cp -a "$file" "$backup"
        printf '%s\t%s\n' "$file" "$backup" >> "$backup_index"
      }

      echo "Updating file keys..."
      for file in ${shellList managedFiles}; do
        sops_file="$(sops_path "$file")"
        [ -s "$sops_file" ] || continue
        echo "  $sops_file"
        backup_file "$sops_file"
        ${sops} updatekeys --yes "$sops_file"
      done

      if [ "$config_changed" -eq 1 ]; then
        echo "Recipient configuration changed; rotating data keys..."
        for file in ${shellList managedFiles}; do
          sops_file="$(sops_path "$file")"
          [ -s "$sops_file" ] || continue
          ${sops} rotate --in-place "$sops_file"
        done
      fi

      mv "$config_tmp" "$sops_config"
      echo "Wrote $sops_config"
      echo "Key-holder files updated. Review the changed sops files and $sops_config."
    '';

  sopsMutationPreamble = ''
    backup_dir="$(mktemp -d)"
    backup_index="$backup_dir/index"
    : > "$backup_index"
    cleanup() {
      status=$?
      if [ "$status" -ne 0 ]; then
        while IFS=$'\t' read -r original backup; do
          [ -n "$original" ] && cp -a "$backup" "$original"
        done < "$backup_index"
      fi
      rm -rf "$backup_dir"
      [ -n "''${__secret_service_key_file:-}" ] && rm -f "$__secret_service_key_file"
      exit "$status"
    }
    trap cleanup EXIT
    backup_file() {
      local file="$1"
      local backup
      backup="$(mktemp "$backup_dir/file.XXXXXX")"
      cp -a "$file" "$backup"
      printf '%s\t%s\n' "$file" "$backup" >> "$backup_index"
    }
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
      adminKeyEnv = secretLib.keySourceEnv service.adminKeySource;
      command = if rotate then "rotate --in-place" else "updatekeys --yes";
      fileRecipients = managedFileRecipients {
        inherit service clusterName clusterConfig;
      };
      files =
        if group == null then
          attrNames fileRecipients
        else
          [
            (secretLib.resolveSopsFileCommand {
              inherit service clusterName;
              scope = "cluster";
              value = "cluster/${group}";
            })
          ];
    in
    ''
      set -euo pipefail
      ${sopsRootPreamble { inherit service clusterName; }}
      export SOPS_CONFIG="$sops_config"
      ${adminKeyEnv}
      if [ -z "${"$"}{SOPS_AGE_KEY_FILE:-}${"$"}{SOPS_AGE_SSH_PRIVATE_KEY_FILE:-}" ]; then
        echo "ERROR: configure services.secrets.adminKeySource, or export SOPS_AGE_KEY_FILE/SOPS_AGE_SSH_PRIVATE_KEY_FILE." >&2
        exit 1
      fi
      ${sopsMutationPreamble}
      for file in ${shellList files}; do
        sops_file="$(sops_path "$file")"
        [ -s "$sops_file" ] || continue
        echo "  $sops_file"
        backup_file "$sops_file"
        ${sops} ${command} "$sops_file"
      done
    '';

  mkInitRootScript =
    { clusterConfig }:
    let
      service = secretLib.serviceOf clusterConfig;
      clusterName = secretLib.clusterNameOf clusterConfig;
      fqdn = clusterConfig.clusters.this.fqdn or "";
      files = attrNames (managedFileRecipients {
        inherit service clusterName clusterConfig;
      });
    in
    ''
      set -euo pipefail
      force=0
      if [ "''${1:-}" = "--force" ]; then
        force=1
      fi
      ${sopsRootResolve service}
      marker="$sops_root/.secret-service-root"
      mkdir -p "$sops_root"
      for file in ${shellList files}; do
        sops_file="$(sops_path "$file")"
        mkdir -p "$(dirname "$sops_file")"
        [ -e "$sops_file" ] || : > "$sops_file"
      done
      if [ -f "$marker" ] && [ "$force" -ne 1 ]; then
        echo "Root marker already exists: $marker"
        echo "Placeholder sops files ensured."
        exit 0
      fi
      root_id="$(cat /proc/sys/kernel/random/uuid)"
      cat > "$marker" <<EOF
schema: 1
rootId: $root_id
clusters:
  - ${clusterName}
fqdn:
  - ${fqdn}
EOF
      echo "Wrote root marker: $marker"
      echo ""
      echo "Add it to Git and re-run Nix:"
      git_root_hint="$flake_root"
      [ -n "$git_root_hint" ] || git_root_hint="$PWD"
      echo "  git -C '$git_root_hint' add -- '$marker'"
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
        clusterConfig
        machine
        machineName
        ;
    });

in
{
  inherit
    mkAdminKeyGenerateScript
    mkCheckScript
    mkInitRootScript
    mkSecretsKeyGenerateAllScript
    mkSecretEditScript
    mkSecretsKeyGenerateScript
    mkSecretSetScript
    mkSyncKeyHoldersScript
    mkUpdateKeysScript
    mkInstallKeyScript
    ;
}
