# Secret Service — Specification

> **Status:** normative target design. The implementation in this directory is being migrated from the previous gocryptfs-based service to sops-nix. This document defines the intended behavior and option surface.

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
| recipient | A public key or key service that can decrypt the file's data key. |
| identity | The private key material used by a recipient. |
| key source | How a target obtains its identity: age key file, KeePass, secure file, SSH host key, or native sops configuration. |
| cluster-scoped secret | Declared under `services.secrets.secrets`; available on every machine selected by the service. |
| machine-scoped secret | Declared under `machines.<machine>.secrets`; available only on that machine. |
| projection | The evaluation-time mapping from cluster configuration to `sops.secrets` / `sops.templates`. |

## 3. Cluster service options

These live under `domain.clusters.<cluster>.services.secrets`.

| Option | Type | Default | Description |
|---|---|---|---|
| `selectors` | framework service option | required | Machines/VMs on which the service is active. |
| `sopsRoot` | path | `./secrets` | Root directory for sops files. |
| `machinesDir` | string | `"machines"` | Subdirectory for per-machine sops files. |
| `clusterDir` | string | `"cluster"` | Subdirectory for cluster group sops files. |
| `clusterSopsFile` | null or path | `null` | Explicit cluster-wide sops file. `null` means `<sopsRoot>/<clusterName>/cluster.yaml`. |
| `secrets` | attrs of attrs of secret | `{}` | Cluster-scoped secrets, projected to every selected node. |
| `templates` | attrs of template | `{}` | Cluster-scoped templates, projected to every selected node. |
| `adminPublicKey` | null or string | `null` | Admin recovery age public key included in every generated creation rule. Required for automated `.sops.yaml` generation. |
| `adminKeySource` | null or key-source submodule | `null` | Identity used by `secretsSyncRecipients` when it needs to decrypt a data key for `sops updatekeys`/`sops rotate`. If null, the command requires an explicitly configured machine key source or manual intervention. |
| `groups` | attrs of list of node names | `{}` | Shared group membership. A group named `monitoring` with members `[ "vm1" "vm2" ]` corresponds to `sopsFile = "cluster/monitoring"`; see [§7.2](#72-string-shorthands). |
| `keepGenerations` | null or int | `null` | Projects to [`sops.keepGenerations`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L237) when non-null. |
| `useTmpfs` | null or bool | `null` | Projects to [`sops.useTmpfs`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L299) when non-null. |
| `log` | null or list of enum | `null` | Projects to [`sops.log`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L245) when non-null. |
| `validateSopsFiles` | null or bool | `null` | Projects to [`sops.validateSopsFiles`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L228) when non-null. |
| `useSystemdActivation` | null or bool | `null` | Projects to [`sops.useSystemdActivation`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L319) when non-null. |
| `environment` | attrs of str/path | `{}` | Merged into [`sops.environment`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L259). Never put secret values here. |

### 3.1 Recipient generation

`secretsSyncRecipients` derives creation rules from:

- `adminPublicKey` for every rule,
- each machine's `deployment.secrets.keySource.publicKey`, or a public key derived from the configured key source when possible,
- `groups` for `cluster/<group>` files; see [§7.2](#72-string-shorthands),
- the resolved service selectors for the cluster-wide file.

If a machine has no public key and the key source cannot be read non-interactively, recipient generation fails with a message identifying the machine. PGP/KMS/Vault recipient generation is backend-specific and may remain manual initially.

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
| `type` | enum `age`, `keepass`, `file`, `ssh`, `native` | `"native"` | Key-source strategy. |
| `publicKey` | null or string | `null` | Expected age public key for verification. |
| `age.keyFile` | path | `/var/lib/sops-nix/key.txt` | Target age key file for `type = "age"`. Must not be in the Nix store. |
| `age.plugins` | list of packages | `[]` | Projected to `sops.age.plugins` for `type = "age"` or `"native"`. |
| `keepass.databasePath` | path/string | required for keepass | KeePass database on the admin machine. |
| `keepass.entry` | string | required for keepass | Entry path, e.g. `hosts/vm1`. |
| `keepass.attachment` | null or string | `null` | Attachment name. If null, the password field is used. |
| `keepass.passwordFile` | null or path | `null` | File containing the KeePass password. |
| `keepass.passwordCommand` | null or string | `null` | Command that prints the KeePass password. |
| `keepass.keyFilePath` | null or path | `null` | KeePass key file. |
| `file.path` | path | required for file | Securely stored local age key file on the admin machine. |
| `ssh.keyPaths` | list of paths | `[ "/etc/ssh/ssh_host_ed25519_key" ]` | Host keys used as age identities for `type = "ssh"`. Projected to `sops.age.sshKeyPaths`. |

`type = "native"` means the cluster service performs no key provisioning or key-file injection. The node must configure `sops.age.*`, `sops.gnupg.*`, `sops.environment` or age plugins itself.

## 5. Secret options

Both `services.secrets.secrets.<user>.<secret>` and `machines.<machine>.secrets.<user>.<secret>` use this schema. The key `templates` is reserved at the `secrets` level for template declarations and is not a valid user name.

These options map directly to the upstream [sops-nix secret options](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L58-L190).

| Option | Type | Default | Description |
|---|---|---|---|
| [`sopsFile`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L50) | string or path | scope default | Which sops file contains the value. See [§7.2 String shorthands](#72-string-shorthands). |
| [`key`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L61) | string | `"<user>/<secret>"` | Path inside the sops file. Uses `/` as separator. |
| [`name`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L53) | string | `"<user>/<secret>"` | Runtime file name under the sops secret store. |
| [`path`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L68) | null or string | `"/run/secrets/<name>"` | Symlink path created by sops-nix. |
| [`owner`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L103) | null or string | `null` (meaning `<user>`) | Runtime owner. |
| [`group`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L116) | null or string | `null` | Runtime group. |
| [`mode`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L97) | string | `"0400"` | Runtime mode, parsed as octal. |
| [`format`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L86) | null or enum `yaml`, `json`, `binary`, `dotenv`, `ini` | `null` (sops default `yaml`) | Secret format. All secrets from one sops file must use the same format. |
| [`restartUnits`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L150) | list of strings | `[]` | Units restarted when the secret changes. |
| [`reloadUnits`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L159) | list of strings | `[]` | Units reloaded when the secret changes. |
| [`neededForUsers`](https://github.com/Mic92/sops-nix/blob/master/modules/sops/default.nix#L168) | bool | `false` | Install before users are created, for hashed passwords. Forces root ownership and the early sops path. |

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
<sopsRoot>/<clusterName>/<machinesDir>/<machineName>.yaml
<sopsRoot>/<clusterName>/cluster.yaml
<sopsRoot>/<clusterName>/<clusterDir>/<groupName>.yaml
```

`clusterSopsFile` overrides the cluster-wide file. `sopsRoot`, `machinesDir` and `clusterDir` are configurable. These paths and the `sopsFile` shorthands are resolved as described in [§7.2](#72-string-shorthands).

### 7.2 String shorthands

| Value | Resolution |
|---|---|
| `"machine"` | `<sopsRoot>/<clusterName>/<machinesDir>/<machineName>.yaml` |
| `"cluster"` | `clusterSopsFile` if set, otherwise `<sopsRoot>/<clusterName>/cluster.yaml` |
| `"cluster/<group>"` | `<sopsRoot>/<clusterName>/<clusterDir>/<group>.yaml` |
| Any other string/path | Treated as an explicit path. |

### 7.3 Resolution

There is no precedence chain:

- If the secret declares `sopsFile`, use it.
- Otherwise use the scope default:
  - machine-scoped secret → `"machine"`
  - cluster-scoped secret → `"cluster"`
- Resolve the value through the shorthands in §7.2.
- If the resolved path or the configured scope file is invalid, fail with an error identifying the secret and the unresolved value. Do not fall back to another file.

Every projected `sops.secrets` entry receives an explicit `sopsFile`. The service never relies on `sops.defaultSopsFile`.

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
- Cluster-scoped secrets are projected for every node selected by the service. Their `sopsFile` defaults to `"cluster"`; see [§7.2](#72-string-shorthands).
- If both define the same `<user>/<secret>`, the machine-scoped secret wins and a Nix warning reports the shadowed cluster secret.
- Duplicate mappings to the same `(sopsFile, key)` within a scope are an evaluation error.

### 8.2 Templates

Templates are projected to `sops.templates` with namespaced names:

```text
<cluster>/<machine>/<template>   # machine-scoped
<cluster>/<template>             # cluster-scoped
```

Template `content` is called with the NixOS `config` so it can use `config.sops.placeholder`.

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
2. The target key file exists and matches the expected public key (age/keepass/file/ssh).
3. Every sops file used by the machine contains the expected recipient, or is recoverable through the admin key.
4. No unexpected machine recipients are present in machine-private files.
5. Every declared key exists in its sops file.
6. Every `sopsFile` is tracked (and reports dirty state).
7. Templates reference declared secrets.
8. `neededForUsers`, owner, group and mode constraints hold.

It must not install, decrypt to persistent storage, or modify the repository.

### 9.3 Evaluation assertions

- exactly one of `owner`/`uid` and `group`/`gid` where relevant,
- all secrets from one `sopsFile` use the same `format`,
- target `owner` and `group` users/groups exist,
- no duplicate `(sopsFile, key)` mappings per scope,
- `neededForUsers` is not combined with non-root ownership,
- template placeholders refer to declared secrets,
- `sopsFile` shorthands resolve to valid paths as defined in [§7.2](#72-string-shorthands).

## 10. Commands

All commands are parameterless except `secretSet`, which takes `--key` and reads the value from stdin. Configuration is embedded at evaluation time.

### 10.1 Machine commands

| Command | Purpose |
|---|---|
| `nix run .#<clusterName>.<machineName>.secretsCheck` | Read-only verification of the key, recipients, declared secrets and templates. |
| `nix run .#<clusterName>.<machineName>.secretsUpdate` | Ensure the host key, verify everything, and deploy the machine. |
| `nix run .#<clusterName>.<machineName>.secretsRemoveOld` | Remove old age identities from the host after the rollback window. |
| `nix run .#<clusterName>.<machineName>.secretEdit` | Edit the machine's default sops file. |
| `nix run .#<clusterName>.<machineName>.secretSet -- --key <user>/<secret>` | Set one machine secret from stdin. |

### 10.2 Cluster commands

| Command | Purpose |
|---|---|
| `nix run .#<clusterName>.secrets.secretsSyncRecipients` | Regenerate `.sops.yaml`, run `sops updatekeys`, and rotate data keys when recipients are removed. |
| `nix run .#<clusterName>.secrets.secretEdit` | Edit the cluster sops file. |
| `nix run .#<clusterName>.secrets.secretSet -- --key <user>/<secret>` | Set one cluster secret from stdin. |
| `nix run .#<clusterName>.secrets.secretUpdateKeys` | Run `sops updatekeys` on the cluster files. |
| `nix run .#<clusterName>.secrets.secretRotate` | Run `sops rotate` on the cluster files. |

The package path determines the scope: a machine command lives under `<clusterName>.<machineName>`, a cluster command under `<clusterName>.secrets`. The helper names do not need a `Cluster` suffix.

### 10.3 `secretsCheck`

Per machine. Read-only. See section 9.2.

### 10.4 `secretsUpdate`

Per machine. Mutating only on the target, not in the repository.

1. Resolve and verify the key source.
2. Install or repair the host key if allowed.
3. Verify the expected public key.
4. Verify recipients and declared keys.
5. Deploy the machine with the normal deploy mechanism.
6. Re-run the checks after deployment.

It does not run `sops updatekeys` or `sops rotate`; repository mutation belongs to `secretsSyncRecipients`.

Dirty/untracked sops files cause failure by default. Development bypass:

```bash
nix run .#<clusterName>.<machineName>.secretsUpdate -- --impure
```

The `--impure` argument is passed to the script, not to Nix. Nix's own `--impure` is separate and does not include untracked files in a Git-backed flake.

### 10.5 `secretsSyncRecipients`

Cluster-level. Mutates the repository and expects a follow-up commit.

1. Generate or validate `.sops.yaml` from `adminPublicKey`, machine public keys and `groups`.
2. Use `adminKeySource` (or an explicitly selected machine key source) to obtain an identity for data-key operations.
3. Run `sops updatekeys` on affected files.
4. For files where a recipient was removed, run `sops rotate --in-place`.
5. Report changed files and require a commit.

### 10.6 `secretsRemoveOld`

Per machine and cluster-level variants. Removes old identities from the host after the configured rollback window. It verifies the current expected key remains and refuses to remove keys still referenced by the current deployment.

It cannot revoke old ciphertext in Git history or the Nix store; see section 12.

### 10.7 `secretEdit`, `secretSet`, `secretUpdateKeys` and `secretRotate`

These are thin wrappers around the corresponding sops commands:

- `secretEdit` opens the default scope file. Machine scope edits the machine file; cluster scope edits the cluster file.
- `secretSet` sets one key in the default scope file. The value is read from stdin.
- `secretUpdateKeys` runs `sops updatekeys` on the cluster files.
- `secretRotate` runs `sops rotate` on the cluster files.

The wrappers use the same path resolution as the projection; see [§7.2](#72-string-shorthands).

## 11. Key sources and provisioning

### 11.1 Default recommendation

A dedicated age key per node. It separates secret access from SSH access, rotates independently, and can be escrowed in KeePass or a secure file.

### 11.2 First installation

The `create` package injects the age key with `nixos-anywhere --extra-files` before `nixos-install` runs activation. It verifies the key's public part before installing. The key is generated into a temporary directory and is never in the Nix store.

### 11.3 Later deployments

`secretsUpdate` checks the key over SSH and can repair it. It requires root/sudo to write `/var/lib/sops-nix/key.txt`.

### 11.4 SSH host keys

When `type = "ssh"`, no key is injected. The host key must exist before activation. `nixos-anywhere --copy-host-keys` can preserve it across installs. Reimaging with a new host key requires re-encryption.

### 11.5 Other backends

- PGP: configure `sops.gnupg.*`; protected keys may prompt and are unsuitable for unattended activation.
- KMS/Vault: configure `sops.environment` and credentials; activation needs network and credentials.
- Age plugins: configure `sops.age.plugins`; hardware-backed plugins may not work unattended.
- `sops.environment` must never contain secret values; use instance roles, agents or credential files.

## 12. Rotation, revocation and rollback

Sops has no mechanism to revoke old ciphertext. Old file versions in Git history or the Nix store remain decryptable by any identity that had access to their data key.

When removing a recipient because a key may be compromised:

1. Remove the key from `.sops.yaml`.
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
- `secretsCheck`/`secretsUpdate` for VMs run on the host. VMs have no individual deployment command.

## 14. Compatibility and migration

- The service must not set `sops.defaultSopsFile` or key-source options that the user did not configure.
- Machine-local `sops.secrets`, `sops.templates` and `sops.*` options merge normally.
- Cluster-generated `sops.secrets` and `sops.templates` names are namespaced.
- Sops files must be tracked by Git for Git-backed flakes; untracked files are invisible to Nix.
- `sops.useSystemdActivation` may switch to a systemd unit automatically when sysusers/userborn is enabled; this is upstream behavior.
- The old gocryptfs archive, metadata, transfer script, `secret-service` user/group and runtime unit are removed after migration.
