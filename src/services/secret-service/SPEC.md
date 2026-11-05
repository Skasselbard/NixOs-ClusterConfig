# Secret Service — Specification

> **Status:** implemented. This document defines the normative behavior and option surface of the sops-nix-based service.

## 1. Scope

The secret service:

- declares secrets at cluster and machine scope in the cluster configuration,
- projects them into sops-nix `sops.secrets` and `sops.templates` declarations,
- uses ordinary sops files for encrypted storage,
- installs secrets on target nodes at NixOS activation time,
- provides parameterless check, update, recipient-sync and old-key-removal commands.

Out of scope:

- generating secret values or certificates,
- per-secret recipient sets inside a single sops file,
- replacing domain modules that know how to generate specific secrets (for example Kubernetes certificates).

## 2. Terminology

| Term | Meaning |
|---|---|
| sops file | A YAML/JSON/dotenv/INI/binary file whose values are encrypted by sops. |
| data key | The symmetric key sops generates per file to encrypt values. |
| decryption key holder | A public key or key service that can decrypt the file's data key. sops calls this a recipient in `.sops.yaml`. |
| identity | The private key material used by a decryption key holder. |
| key source | How a target obtains its identity: age key file, KeePass, SSH host key, or native sops configuration. |
| cluster-scoped secret | Declared under `services.secrets.secrets`; available on every machine selected by the service. |
| machine-scoped secret | Declared under `machines.<machine>.secrets`; available only on that machine. |
| projection | The evaluation-time mapping from cluster configuration to `sops.secrets` / `sops.templates`. |

## 3. Cluster service options

These live under `domain.clusters.<cluster>.services.secrets`.

| Option | Type | Default | Description |
|---|---|---|---|
| `selectors` | framework service option | required | Machines/VMs on which the service is active. |
| `sopsRoot` | path or `{ nixPath, osPath }` | required | Root directory for sops files. The normal form is `./secrets`; the explicit form supplies both projection and helper paths. The generated sops configuration is `<sopsRoot>/.sops.yaml`. |
| `machinesSubDir` | string | `"machines"` | Subdirectory for per-machine sops files. |
| `clusterSubDir` | string | `"cluster"` | Subdirectory for cluster group sops files. |
| `clusterSopsFile` | null or string | `null` | Explicit cluster-wide sops file. `null` means `<sopsRoot>/<clusterName>/cluster.yaml`. |
| `secrets` | attrs of attrs of secret | `{}` | Cluster-scoped secrets, projected to every selected node. |
| `templates` | attrs of template | `{}` | Cluster-scoped templates, projected to every selected node. |
| `adminKeySource` | key-source submodule | required | Admin decryption key holder and identity used by `secretsSyncKeyHolders`. Its public key is derived from the key source at runtime and is included in every generated rule. |
| `groups` | attrs of list of node names | `{}` | Cluster-local secret groups. A group named `monitoring` with members `[ "vm1" "vm2" ]` corresponds to `sopsFile = "cluster/monitoring"` and is projected only to those nodes. These are not OS groups. |
| `keepGenerations` | null or int | `null` | Projects to [`sops.keepGenerations`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L237) when non-null. |
| `useTmpfs` | null or bool | `null` | Projects to [`sops.useTmpfs`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L299) when non-null. |
| `log` | null or list of enum | `null` | Projects to [`sops.log`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L245) when non-null. |
| `validateSopsFiles` | null or bool | `null` | Projects to [`sops.validateSopsFiles`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L228) when non-null. |
| `useSystemdActivation` | null or bool | `null` | Projects to [`sops.useSystemdActivation`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L319) when non-null. |
| `environment` | attrs of str/path | `{}` | Merged into [`sops.environment`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L259). Never put secret values here. |

### 3.1 Recipient generation

`secretsSyncKeyHolders` derives creation rules from:

- a public key derived from `adminKeySource` for every rule,
- a public key derived from each machine's `deployment.secrets.keySource`,
- `native.publicKey` or `native.publicKeyFile` for `type = "native"`,
- `groups` for `cluster/<group>` files; see [§7.2](#72-string-shorthands),
- the resolved service selectors for the cluster-wide file.

Managed public keys are never stored in the cluster configuration. They are derived at runtime:

- `age`: `age-keygen -y age.sourceKeyFile`
- `keepass`: extract the private key, then `age-keygen -y`
- `ssh`: `ssh-keygen -y` piped to `ssh-to-age`
- `native`: explicit `native.publicKey` / `native.publicKeyFile`

If a machine uses a target-only key source and its key is not readable on the build host, recipient generation fails with a message identifying the machine.

### 3.2 sops-nix defaults

The root-level sops options are projected with `lib.mkDefault`, so machine-level `sops.*` definitions take precedence. They map directly to the upstream [sops-nix options](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L203-L337).

The service never sets `sops.defaultSopsFile`. Each generated secret gets an explicit `sopsFile`.

## 4. Machine/node options

These live under `machines.<machine>` (and are also available on VMs where applicable).

| Option | Type | Default | Description |
|---|---|---|---|
| `deployment.secrets.keySource` | submodule | `{ type = "native"; }` | How the node obtains its sops identity. |
| `secrets` | attrs of attrs of secret plus `templates` | `{}` | Machine-scoped secrets and templates. |

### 4.1 `deployment.secrets.keySource`

| Option | Type | Default | Description |
|---|---|---|---|
| `type` | enum `age`, `keepass`, `ssh`, `native` | `"native"` | Key-source strategy. |
| `targetKeyFile` | string | `/var/lib/sops-nix/key.txt` | Target key path for `age` and `keepass`. |
| `age.sourceKeyFile` | null or string | required for age | Build-host private age key. A string, not a Nix path, so it is not copied into the store. |
| `keepass.databasePath` | null or string | required for keepass | KeePass database path on the admin machine. A host/working-tree string, not a Nix path. |
| `keepass.entry` | string | `clusterConfig/<cluster>/admin` for the admin source; `clusterConfig/<cluster>/machines/<machine>` for machine sources | Entry path. The password field contains the age private key. |
| `keepass.passwordFile` | null or string | `null` | File containing the KeePass password. Kept as a string so it is not copied into the Nix store. |
| `keepass.passwordCommand` | null or string | `null` | Command that prints the KeePass password. Use instead of `passwordFile`. |
| `keepass.keyFilePath` | null or string | `null` | KeePass key file. A host/working-tree string, not a Nix path. |
| `native.publicKey` | null or string | `null` | Public recipient for native recipient generation. |
| `native.publicKeyFile` | null or string/path | `null` | File containing the native public recipient. |
| `ssh.keyPaths` | list of strings | `[ "/etc/ssh/ssh_host_ed25519_key" ]` | Host keys used as age identities for `type = "ssh"`. Host/working-tree strings, not Nix paths. Projected to `sops.age.sshKeyPaths`. |

`type = "native"` means the cluster service performs no key provisioning or key-file injection. The node must configure `sops.age.*`, `sops.gnupg.*`, `sops.environment` or age plugins itself.

## 5. Secret options

Both `services.secrets.secrets.<user>.<secret>` and `machines.<machine>.secrets.<user>.<secret>` use this schema. The key `templates` is reserved at the `secrets` level for template declarations and is not a valid user name.

These options map directly to the upstream [sops-nix secret options](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L58-L190).

| Option | Type | Default | Description |
|---|---|---|---|
| `sopsFile` | string | scope default | Which sops file contains the value. Relative explicit paths resolve under `sopsRoot`. See [§7.2](#72-string-shorthands). |
| [`key`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L61) | string | `"<user>/<secret>"` | Path inside the sops file. Uses `/` as separator. |
| [`name`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L53) | string | `"<user>/<secret>"` | Runtime name used to derive the default `path`. The internal sops identity remains the cluster-qualified attribute key, so changing `name` does not affect template placeholders. |
| [`path`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L68) | null or string | `"/run/secrets/<name>"` | Symlink path created by sops-nix. |
| [`owner`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L103) | null or string | `null` (meaning `<user>`) | Runtime owner. |
| [`group`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L116) | null or string | `null` | Runtime group. |
| [`mode`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L97) | string | `"0400"` | Runtime mode, parsed as octal. |
| [`format`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L86) | null or enum `yaml`, `json`, `binary`, `dotenv`, `ini` | `null` (sops default `yaml`) | Secret format. All secrets from one sops file must use the same format. |
| [`restartUnits`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L150) | list of strings | `[]` | Units restarted when the secret changes. |
| [`reloadUnits`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L159) | list of strings | `[]` | Units reloaded when the secret changes. |
| [`neededForUsers`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L168) | bool | `false` | Install before users are created, for hashed passwords. Forces root ownership and the early sops path. |

The projected `sops.secrets` attribute key is the stable identity: `<cluster>/<user>/<secret>`. sops-nix uses the same value internally as the manifest secret name and placeholder lookup key. The `name` option only changes the default runtime path; `path` overrides it entirely. This keeps `config.sops.placeholder."<cluster>/<user>/<secret>"` stable even when a custom runtime name is set.

### 5.1 `neededForUsers` special case

When `neededForUsers = true`:

- `owner` and `group` are forced to root (or omitted so sops-nix defaults apply),
- `path` defaults to `/run/secrets-for-users/<name>`,
- the secret is intended for `users.users.<user>.hashedPasswordFile` or equivalent early user setup,
- it is not a normal user-owned file and must not be combined with a user-specific owner/group expectation.

## 6. Template options

Both `services.secrets.templates.<name>` and `machines.<machine>.secrets.templates.<name>` use this schema. These options map to the upstream [sops-nix template options](https://github.com/Mic92/sops-nix/blob/master/modules/sops/templates/default.nix#L16-L150).

| Option | Type | Default | Description |
|---|---|---|---|
| `sopsFile` | null or string | `null` | Optional secret-group scope marker. `cluster/<group>` limits projection to that group; the template is not encrypted. |
| [`content`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/templates/default.nix#L40) | function `{ config, lib, pkgs, ... }: string` | required | Template content, evaluated in NixOS module context. |
| [`path`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/templates/default.nix#L34) | string | required | Runtime path for the rendered file. |
| [`owner`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/templates/default.nix#L54) | null or string | `null` | Runtime owner. |
| [`group`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/templates/default.nix#L68) | null or string | `null` | Runtime group. |
| [`mode`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/templates/default.nix#L47) | string | `"0400"` | Runtime mode. |
| [`restartUnits`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/templates/default.nix#L92) | list of strings | `[]` | Units restarted when the template changes. |
| [`reloadUnits`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/templates/default.nix#L101) | list of strings | `[]` | Units reloaded when the template changes. |

Template content should use namespaced placeholders:

```nix
content = { config }: ''
  token: ${config.sops.placeholder."<cluster>/monitoring/token"}
'';
```

Templates cannot reference `neededForUsers` secrets.

## 7. File layout and `sopsFile` resolution

### 7.1 Default layout

```text
<sopsRoot>/.sops.yaml
<sopsRoot>/.secret-service-root
<sopsRoot>/<clusterName>/<machinesSubDir>/<machineName>.yaml
<sopsRoot>/<clusterName>/cluster.yaml
<sopsRoot>/<clusterName>/<clusterSubDir>/<groupName>.yaml
```

`clusterSopsFile` overrides the cluster-wide file. `sopsRoot`, `machinesSubDir` and `clusterSubDir` are configurable. Helpers locate the nearest enclosing `flake.nix` and may run from any directory inside the flake. With an absolute `sopsRoot.osPath`, helpers may also run outside the flake; relative key-source paths then resolve from the current directory, so use absolute key-source paths or run inside the flake. Without `osPath`, helpers require an enclosing flake and Git checkout. These paths and the `sopsFile` shorthands are resolved as described in [§7.2](#72-string-shorthands).

### 7.2 String shorthands

| Value | Resolution |
|---|---|
| `"machine"` | `<sopsRoot>/<clusterName>/<machinesSubDir>/<machineName>.yaml` |
| `"cluster"` | `clusterSopsFile` if set, otherwise `<sopsRoot>/<clusterName>/cluster.yaml` |
| `"cluster/<group>"` | `<sopsRoot>/<clusterName>/<clusterSubDir>/<group>.yaml` |
| Any other string | Explicit path. Relative values resolve under `sopsRoot`; absolute values are allowed. |

### 7.3 Resolution

There is no precedence chain:

- If the secret declares `sopsFile`, use it.
- Otherwise use the scope default:
  - machine-scoped secret → `"machine"`
  - cluster-scoped secret → `"cluster"`
- Resolve the value through the shorthands in §7.2.
- If the resolved path or the configured scope file is invalid, fail with an error identifying the secret and the unresolved value. Do not fall back to another file.

Every projected `sops.secrets` entry receives an explicit `sopsFile`. The service never relies on `sops.defaultSopsFile`.

### 7.4 Root marker

The sops root contains a committed `.secret-service-root` marker with schema version `1`, a non-empty random `rootId`, cluster names and FQDN. Evaluation tolerates a missing marker; mutating helpers require it, validate the schema and `rootId`, verify that the current cluster is listed, and compare the evaluated marker with the working-tree marker. `secretsInitRoot` creates the marker and empty placeholder sops files during bootstrap; it is safe to repeat. `secretSet` creates an encrypted file when its placeholder is empty. The marker contains no secrets and is a safety guard, not an authorization boundary.

## 8. Projection rules

For each effective secret `<cluster>`, `<user>`, `<secret>`:

```nix
sops.secrets."<cluster>/<user>/<secret>" = {
  sopsFile = <resolved sops file>;
  key = <secret.key>;              # default "<user>/<secret>"
  name = <secret.name>;            # default "<user>/<secret>"
  owner = <secret.owner or user>;  # root when neededForUsers
  group = <secret.group>;
  mode = <secret.mode>;            # default "0400"
  path = <secret.path>;            # default "/run/secrets/<name>"
  format = <secret.format> when set;
  restartUnits = <secret.restartUnits>;
  reloadUnits = <secret.reloadUnits>;
  neededForUsers = <secret.neededForUsers>;
};
```

The Nix attribute name is namespaced by cluster. The sops `key` is **not** automatically namespaced; it stays a user-authored path inside the file. The default convention is `<user>/<secret>` in nested YAML.

### 8.1 Machine vs cluster scope

- Machine-scoped secrets are projected only for that machine. Their `sopsFile` defaults to `"machine"`; see [§7.2](#72-string-shorthands).
- Cluster-scoped secrets are projected to every selected node unless they use a secret-group file.
- A cluster-scoped secret without `sopsFile` is a global secret stored in `cluster.yaml`; its key holders are all selected nodes plus the admin key.
- A cluster-scoped secret with `sopsFile = "cluster/<group>"` is projected only to members of that cluster-local secret group; its key holders are the group members plus the admin key.
- Global and group secrets share the same `services.secrets.secrets.<user>.<secret>` namespace. Use different names if both scopes are needed.
- If both define the same `<user>/<secret>`, the machine-scoped secret wins and a Nix warning reports the shadowed cluster secret.
- Duplicate mappings to the same `(sopsFile, key)` are an evaluation error.

### 8.2 Templates

Templates are projected to `sops.templates` with namespaced names:

```text
<cluster>/<machine>/<template>   # machine-scoped
<cluster>/<template>             # cluster-scoped
```

Template `content` is called with the NixOS `config` so it can use `config.sops.placeholder`. Cluster templates are projected to every selected node by default and must reference only cluster-wide secrets. Setting `sopsFile = "cluster/<group>"` on a template is a scope marker that limits projection to that secret group; the template is not encrypted. Use machine templates for machine-only values.

### 8.3 Namespacing convention

- `sops.secrets` attribute: `<cluster>/<user>/<secret>`.
- sops `key`: default `<user>/<secret>`, never auto-prefixed.
- runtime `name`: default `<user>/<secret>`; one cluster per machine avoids collisions.
- If a sops file is intentionally shared across clusters, the user must namespace the keys inside the file and set `key` explicitly. The file path still follows [§7.2](#72-string-shorthands). This is a documented exception.

## 9. Validation

### 9.1 Build-time checks

- `sops.validateSopsFiles = true` (sops-nix default) builds a manifest and runs `sops-install-secrets -check-mode=sopsfile`.
- That check parses encrypted YAML/JSON without decrypting and verifies that every declared `key` exists.
- Missing keys fail the build.
- The check does not cover binary/dotenv/INI key existence, empty values, or value types.

### 9.2 `secretsCheck`

Read-only, per machine. It verifies:

1. The configured key source is resolvable.
2. The target key file exists and its derived public key matches the configured source (age/keepass).
3. Every sops file used by the machine has exactly the expected recipients: the machine, the relevant secret group or cluster selection, and the admin key.
4. No unexpected age recipients are present. Recipient comparison requires structured YAML/JSON metadata; binary files are reported as skipped.
5. Every declared key decrypts from its sops file.
6. Template placeholders reference declared secrets at evaluation time.
7. `neededForUsers`, owner and group constraints hold where evaluable.

It must not install, decrypt to persistent storage, or modify the repository.

### 9.3 Evaluation assertions

- exactly one of `owner`/`uid` and `group`/`gid` where relevant,
- all secrets from one `sopsFile` use the same `format`,
- target `owner` and `group` users/groups exist,
- no duplicate `(sopsFile, key)` mappings,
- `neededForUsers` is not combined with non-root ownership,
- template placeholders refer to declared secrets,
- `sopsFile` shorthands resolve to valid paths as defined in [§7.2](#72-string-shorthands).

## 10. Commands

All commands are parameterless except `secretSet`, which takes `--key` and reads the value from stdin. Configuration is embedded at evaluation time.

### 10.1 Machine commands

| Command | Purpose |
|---|---|
| `nix run .#<clusterName>.<machineName>.secretsCheck` | Read-only verification of the key, recipients, declared secrets and templates. |
| `nix run .#<clusterName>.<machineName>.secretsInstallKey` | Install or repair the host key only. |
| `nix run .#<clusterName>.<machineName>.secretsKeyGenerate [-- --force]` | Generate a key into `age.sourceKeyFile` or the KeePass entry. |
| `nix run .#<clusterName>.secrets.secretsAdminKeyGenerate [-- --force]` | Generate or update the admin key source. |
| `nix run .#<clusterName>.secrets.secretsKeyGenerateAll [-- --force]` | Generate all managed admin and host keys. |
| `nix run .#<clusterName>.<machineName>.secretEdit` | Edit the machine's default sops file. |
| `nix run .#<clusterName>.<machineName>.secretSet -- --key <user>/<secret>` | Set one declared machine secret from stdin. |

### 10.2 Cluster commands

| Command | Purpose |
|---|---|
| `nix run .#<clusterName>.secrets.secretsInitRoot` | Create the initial secret-root marker and empty placeholder sops files. |
| `nix run .#<clusterName>.secrets.secretsSyncKeyHolders` | Regenerate `<sopsRoot>/.sops.yaml`, run `sops updatekeys`, and rotate data keys when recipients changed. |
| `nix run .#<clusterName>.secrets.secretsRotate` | Rotate data keys for all managed sops files. |
| `nix run .#<clusterName>.secrets.secretEdit` | Edit the cluster sops file. |
| `nix run .#<clusterName>.secrets.secretSet -- --key <user>/<secret>` | Set one declared cluster secret from stdin; group files are inferred. |
| `nix run .#<clusterName>.secrets.secretUpdateKeys` | Run `sops updatekeys` on all managed files. |
| `nix run .#<clusterName>.secrets.secrets<Group>Edit` | Edit a group sops file. |
| `nix run .#<clusterName>.secrets.secrets<Group>Set -- --key <user>/<secret>` | Set one declared group secret from stdin. |
| `nix run .#<clusterName>.secrets.secrets<Group>UpdateKeys` | Run `sops updatekeys` on one group file. |
| `nix run .#<clusterName>.secrets.secrets<Group>Rotate` | Run `sops rotate` on one group file. |

The package path determines the scope: a machine command lives under `<clusterName>.<machineName>`, a cluster or group command under `<clusterName>.secrets`. Group names are capitalized and `-` is replaced with `_` in package names.

### 10.3 `secretsCheck`

Per machine. Read-only. See section 9.2.

### 10.4 `secretsInstallKey`

Per machine. Mutating only on the target, not in the repository.

1. Resolve and verify the key source.
2. Install or repair the host key if allowed.
3. Derive the expected public key from the key source and verify the installed identity.

It does not deploy the system. Secret activation happens when the normal system closure is deployed. It does not run `sops updatekeys` or `sops rotate`; repository mutation belongs to `secretsSyncKeyHolders`.

### 10.5 `secretsSyncKeyHolders`

Cluster-level. Mutates the repository and reports the changed files.

1. Derive public keys at runtime from `adminKeySource`, managed machine key sources, groups and custom sops files, then generate `<sopsRoot>/.sops.yaml`.
2. Build the managed file set from machine files, group files, the cluster file and explicit `sopsFile` paths.
3. Run `sops updatekeys` on managed files.
4. If the generated `<sopsRoot>/.sops.yaml` changed, rotate data keys for all managed files.
5. Stage changes and restore prior file contents on failure.
6. Report changed files.

Native key sources without a manual public key are skipped and reported as unmanaged.

### 10.6 `secretsRotate`

Cluster-level. Rotates data keys for every managed sops file. It does not regenerate host identities and does not rewrite `<sopsRoot>/.sops.yaml`.

### 10.7 `secretsKeyGenerate`

Per machine. Generates a key directly in the configured key source.

- `age`: writes `age.sourceKeyFile`; refuses to overwrite without `--force`.
- `keepass`: creates missing entry parent groups, updates the configured entry password, and refuses to overwrite without `--force`.
- `ssh`: derives and prints the public recipient; does not rotate host keys.
- `native`: unsupported.

The public key is derived from the resulting private key; it is not written to cluster configuration.

### 10.8 `secretEdit`, `secretSet`, `secretUpdateKeys` and `secretsRotate`

These are thin wrappers around the corresponding sops commands:

- `secretEdit` opens the default scope file. Machine scope edits the machine file; cluster scope edits the cluster file; group commands edit their group file.
- `secretSet` sets one declared key in the file inferred from its declaration. The value is read from stdin. Cluster declarations with `sopsFile = "cluster/<group>"` map to the group file, whichever set command is used. Undeclared keys fail with a hint naming the command that owns the declaration. Validation happens before the key source is read.
- `secretUpdateKeys` runs `sops updatekeys` on all managed files.
- `secretsRotate` runs `sops rotate` on all managed files.

Group-specific `Set` commands remain explicit group-file targets.

The wrappers use the same path resolution as the projection; see [§7.2](#72-string-shorthands).

## 11. Key sources and provisioning

### 11.1 Default recommendation

A dedicated age key per node. It separates secret access from SSH access, rotates independently, and can be escrowed in KeePass or an age-key file.

### 11.2 First installation

The `create` package injects additional files with `nixos-anywhere --extra-files` before `nixos-install` runs activation. The secret service contributes entries to the generic `deployment.extraFiles` option. Each entry has either a string `source` path or a `command` that prints the file content at deployment time. File content is copied into a temporary staging directory at runtime and never enters the Nix store.

### 11.3 Later deployments

`secretsInstallKey` installs or replaces the key over SSH. It requires root/sudo to write the target key file, normally `/var/lib/sops-nix/key.txt`. For managed key sources, activation runs a preflight check first and prints the machine-specific `secretsInstallKey` command if the key file is missing.

### 11.4 SSH host keys

When `type = "ssh"`, no key is injected. The host key must exist before activation. `nixos-anywhere --copy-host-keys` can preserve it across installs. Reimaging with a new host key requires re-encryption.

### 11.5 Other backends

- PGP: configure `sops.gnupg.*`; protected keys may prompt and are unsuitable for unattended activation.
- KMS/Vault: configure `sops.environment` and credentials; activation needs network and credentials.
- Age plugins: configure `sops.age.plugins`; hardware-backed plugins may not work unattended.
- `sops.environment` must never contain secret values; use instance roles, agents or credential files.

## 12. Rotation, revocation and rollback

Sops has no mechanism to revoke old ciphertext. Old file versions in Git history or the Nix store remain decryptable by any identity that had access to their data key.

When removing a decryption key holder because a key may be compromised:

1. Remove the key from `<sopsRoot>/.sops.yaml`.
2. `sops updatekeys` on affected files.
3. `sops rotate --in-place` on affected files.
4. Commit.
5. Rotate the actual secret values.

For rollback, keep the old host identity for a bounded window or in KeePass, and use the admin recovery key as the long-term fallback. Do not keep old keys on hosts indefinitely.

## 13. VMs

- VMs get their own age keys; they do not share host secrets.
- The host writes a per-VM key file, for example `/var/lib/sops-nix/vms/<vm>/age.key`.
- A per-VM microvm share exposes the key to the guest, for example at `/run/host-sops/age.key`.
- The guest config sets `sops.age.keyFile` to the shared path.
- The host necessarily has access to VM keys because it controls the VM; isolation is between VMs, not from the host.
- `secretsCheck`/`secretsInstallKey` for VMs run on the host. VMs have no individual deployment command.

## 14. Compatibility and migration

- The service must not set `sops.defaultSopsFile` or key-source options that the user did not configure.
- Machine-local `sops.secrets`, `sops.templates` and `sops.*` options merge normally.
- Cluster-generated `sops.secrets` and `sops.templates` names are namespaced.
- Sops files must be tracked by Git for Git-backed flakes; untracked files are invisible to Nix.
- `sops.useSystemdActivation` may switch to a systemd unit automatically when sysusers/userborn is enabled; this is upstream behavior.
- The old gocryptfs archive, metadata, transfer script, `secret-service` user/group and runtime unit are removed.
