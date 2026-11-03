# Secret Service

> **Status:** implemented. The service now uses sops-nix and age. `SPEC.md` is the normative option and behavior reference; `DECISIONS.md` records why the design looks the way it does.

The secret service lets you declare secrets in the cluster configuration and have them installed on the correct target nodes with the correct owner, group, mode and path.

It uses [sops-nix](https://github.com/Mic92/sops-nix) for the runtime side and normal sops files for storage.

## What it gives you

- Secrets are declared in defined placeholders: the cluster configuration under `machines.<machine>.secrets` and `services.secrets.secrets`.
- Secret values live in ordinary sops files, usually committed to the repository in encrypted form.
- Each machine has its own sops file by default, so a compromised machine cannot decrypt another machine's secrets.
- Secrets are decrypted on the target at activation time and written to a RAM-backed secret store.
- Per-secret `owner`, `group`, `mode`, `path`, `restartUnits` and `reloadUnits` are supported.
- Templates can render configuration files from several secrets. A cluster template may set `sopsFile = "cluster/<group>"` to limit projection to that secret group; the template itself is not encrypted. Without `sopsFile`, a cluster template is projected to every selected node and must use cluster-wide secrets.
- KeePass can be used as the key escrow for the small number of age keys. It is not a data backend and is not required on target machines.
- Other sops key methods are supported through native sops-nix configuration: age key files, SSH keys as age identities, PGP, cloud KMS, Vault Transit and age plugins.

## Design at a glance

```text
cluster configuration
  machines.<machine>.secrets.<user>.<secret>
  services.secrets.secrets.<user>.<secret>
            |
            v  projection during Nix evaluation
  sops.secrets.<cluster>/<user>/<secret>
            |
            v  nixos-rebuild / colmena
  encrypted sops file in the system closure
            |
            v  activation on the target
  sops-install-secrets
    - decrypts with the host age key
    - writes to ramfs
    - sets owner/group/mode
    - creates symlinks at the configured paths
    - restarts/reloads configured units
```

## sops-nix in two minutes

A sops file is a structured file whose values are encrypted while its keys stay readable:

```yaml
admin:
  testPassword: ENC[AES256_GCM,data:...,type:str]
  tlsKey: ENC[AES256_GCM,data:...,type:str]
sops:
  age:
    - recipient: age1...
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
```

A random **data key** encrypts the values. The data key is itself encrypted to one or more **decryption key holders**: age public keys whose matching private identity can decrypt the file. All values in one sops file share the same key holders, so the file is the isolation boundary.

`.sops.yaml` decides which key holders are used for which file. sops calls these entries “recipients”. `sops edit`, `sops set`, `sops updatekeys` and `sops rotate` are the normal editing and key-management tools.

sops-nix reads `sops.secrets` declarations from the NixOS configuration, builds a manifest, and during activation runs `sops-install-secrets`. That helper decrypts each secret, writes the real file into a RAM-backed directory, applies ownership and permissions, creates symlinks at the configured paths, and restarts configured units. The plaintext never goes into the Nix store.

## Default file layout

```text
secrets/
├── .sops.yaml                # generated creation rules
├── .secret-service-root     # committed root marker
└── <cluster-name>/
    ├── machines/
    │   ├── <machine>.yaml     # only that machine + admin recovery key
    │   └── ...
    ├── cluster.yaml           # all selected machines in the cluster + admin
    └── cluster/
        ├── <group>.yaml       # the machines in that group + admin
        └── ...
```

The layout is configurable. `sopsFile` accepts these shorthands:

| Value | Meaning |
|---|---|
| `"machine"` | The machine's own file. This is the default for machine-scoped secrets. |
| `"cluster"` | The cluster-wide sops file. This is the default for cluster-scoped secrets. |
| `"cluster/<group>"` | A shared group file under the cluster directory. |
| An explicit path | Any other sops file. |

A machine belongs to exactly one cluster, which keeps the runtime secret names simple.

### Global, group and machine secrets

| Declaration | `sopsFile` | Can decrypt |
|---|---|---|
| `services.secrets.secrets.<user>.<secret>` without `sopsFile` | `"cluster"` → `cluster.yaml` | all selected nodes + admin key |
| `services.secrets.secrets.<user>.<secret>` with `sopsFile = "cluster/<group>"` | group file | members of that group + admin key |
| `machines.<machine>.secrets.<user>.<secret>` | machine file | that machine + admin key |

Global secrets are useful for values every selected node needs, such as a shared service password. They are not admin-only. Use a group or machine file when access should be narrower.

## Quick start

### 1. Enable the service

```nix
services.secrets = {
  selectors = [ filters.clusterMachines ];

  # Helpers may run from any directory inside this flake.
  sopsRoot = ./secrets;
  machinesSubDir = "machines";
  clusterSubDir = "cluster";

  # The admin key is a key holder for every generated rule and the identity
  # used by key-holder management commands.
  adminKeySource = {
    type = "age";
    # A string, not a Nix path, so the private key is not copied into the store.
    age.sourceKeyFile = "/path/to/admin.key";
  };

  # Optional shared groups for "cluster/<group>" sops files.
  groups.monitoring = [ "vm1" "vm2" ];
};
```

### 2. Configure the key source for a machine

The recommended default is a dedicated age key per machine. KeePass can hold that key during provisioning and recovery.

```nix
machines.vm1 = {
  deployment.secrets.keySource = {
    type = "keepass";
    keepass = {
      databasePath = "/home/user/secrets.kdbx";
      # entry defaults to clusterConfig/<cluster>/machines/<machine>

      # Choose one password source.
      passwordFile = "/run/keys/keepass.pass";
      # passwordCommand = "secret-tool lookup service keepass database example";
    };
  };
};
```

Supported key-source types are `age`, `keepass`, `ssh` and `native`. `age` always requires a build-host `age.sourceKeyFile`; the target key file is provisioned from it. `keepass` extracts the private age key from the configured entry and creates missing parent groups during key generation. `native` is manually managed; configure `sops.*` yourself, including age plugins.

Password sources, in preference order:

1. `passwordFile` pointing to a `0600` file outside the Nix store.
2. `passwordCommand` using an OS keyring or secret manager, for example `secret-tool`, `pass` or `gopass`.
3. `passwordCommand` reading a password-file path from an environment variable, for example:
   ```nix
   passwordCommand = "cat \"\${KEEPASS_PASSWORD_FILE:?set KEEPASS_PASSWORD_FILE}\"";
   ```
4. An environment variable containing the password directly. This is convenient but weaker: environment variables can leak through `/proc`, child processes, crash reports and CI logs.

```nix
# Password-file variant:
passwordFile = "../00-exampleConfigs/secrets/keepass.pass";

# Password-command variant:
passwordCommand = "cat \"\${KEEPASS_PASSWORD_FILE:?set KEEPASS_PASSWORD_FILE}\"";
```

Generate or replace a key directly in its source:

```bash
# file-backed age key: requires --force to overwrite
nix run .#<cluster>.<machine>.secretsKeyGenerate -- --force

# KeePass entry: requires --force to overwrite an existing entry
nix run .#<cluster>.<machine>.secretsKeyGenerate -- --force
```

Public keys are derived at runtime from `age.sourceKeyFile`, the KeePass entry or the SSH key. They are not configured in the cluster options.

### 3. Generate or update `.sops.yaml`

```bash
nix run .#<cluster>.secrets.secretsSyncKeyHolders
```

This derives public keys from the machine and admin key sources at runtime, generates `<sopsRoot>/.sops.yaml`, runs `sops updatekeys` and rotates data keys.

### 4. Declare secrets

Machine-scoped secrets:

```nix
machines.vm1.secrets.admin = {
  testPassword = {
    path = "/home/admin/secrets/testPassword";
    mode = "440";
  };
};
```

Cluster-scoped secrets are available on every machine selected by the service:

```nix
services.secrets.secrets.monitoring = {
  token = {
    sopsFile = "cluster";
    path = "/run/secrets/monitoring-token";
    owner = "monitoring";
    mode = "0400";
  };
};
```

A machine-scoped secret with the same `<user>/<secret>` name overrides a cluster-scoped secret. The override is announced with a Nix warning.

### 5. Create or edit the sops file

```bash
nix run .#example.vm1.secretEdit
```

The sops key path is the secret's `<user>/<secret>` path by default, for example `admin/testPassword`. Use nested YAML:

```yaml
admin:
  testPassword: hunter2
```

### 6. Check and deploy

```bash
nix run .#example.vm1.secretsCheck
nix run .#example.vm1.secretsInstallKey
```

`secretsCheck` is read-only. `adminKeySource` is required; it is the recovery recipient for every generated sops file. `secretsInstallKey` only installs or repairs the host key. Secret changes are deployed through the normal system closure, so there is no separate secret-transfer step.

## Commands

Most commands are parameterless. Everything they need is embedded at Nix evaluation time. `secretSet` is the exception: it takes `--key` and reads the value from stdin.

| Command | Purpose |
|---|---|
| `nix run .#<clusterName>.<machineName>.secretsCheck` | Read-only verification of the key, decryption key holders, declared secrets and templates. |
| `nix run .#<clusterName>.<machineName>.secretsInstallKey` | Install or repair the host key only. |
| `nix run .#<clusterName>.<machineName>.secretsKeyGenerate [-- --force]` | Generate a new key into its age source or KeePass entry. |
| `nix run .#<clusterName>.<machineName>.secretEdit` | Edit the machine's default sops file. |
| `nix run .#<clusterName>.<machineName>.secretSet -- --key <user>/<secret>` | Set one machine secret from stdin. |
| `nix run .#<clusterName>.secrets.secretsInitRoot` | Create the initial secret-root marker. Required once per secret root. |
| `nix run .#<clusterName>.secrets.secretsSyncKeyHolders` | Derive public keys, regenerate `<sopsRoot>/.sops.yaml`, run `sops updatekeys`, and rotate data keys when recipients changed. |
| `nix run .#<clusterName>.secrets.secretsRotate` | Rotate data keys for every managed sops file. |
| `nix run .#<clusterName>.secrets.secretEdit` | Edit the cluster sops file. |
| `nix run .#<clusterName>.secrets.secretSet -- --key <user>/<secret>` | Set one cluster secret from stdin. |
| `nix run .#<clusterName>.secrets.secretUpdateKeys` | Run `sops updatekeys` on all managed files. |
| `nix run .#<clusterName>.secrets.secretRotate` | Run `sops rotate` on all managed files. |
| `nix run .#<clusterName>.secrets.secret<Group>Edit` | Edit a group sops file, for example `secretMonitoringEdit`. |
| `nix run .#<clusterName>.secrets.secret<Group>Set -- --key <user>/<secret>` | Set one group secret from stdin. |
| `nix run .#<clusterName>.secrets.secret<Group>UpdateKeys` | Run `sops updatekeys` on one group file. |
| `nix run .#<clusterName>.secrets.secret<Group>Rotate` | Run `sops rotate` on one group file. |

The package path determines the scope: machine commands live under `<clusterName>.<machineName>`, cluster and group commands under `<clusterName>.secrets`. Group names are capitalized and `-` is replaced with `_` in package names.

## Key sources

| Type | Behavior |
|---|---|
| `age` | A build-host `age.sourceKeyFile` is installed to `targetKeyFile`, normally `/var/lib/sops-nix/key.txt`. |
| `keepass` | The helper extracts the age key from a KeePass entry during setup/recovery and installs it to `targetKeyFile`. KeePass is not needed at boot. |
| `ssh` | The target's SSH host key is used as the age identity. No key injection is needed, but the host key must exist before activation and reimaging requires re-encryption. Public-key derivation requires a locally readable key. |
| `native` | Manually managed. Set `native.publicKey` or `native.publicKeyFile` if sync should include it as an age recipient. Native PGP/KMS/Vault rules are not generated by this service; `secretsSyncKeyHolders` rewrites `<sopsRoot>/.sops.yaml`, so keep manual native rules outside that managed file. |

Dedicated age keys are the default recommendation because they rotate independently from SSH access and have a clear recovery path. SSH keys are supported for convenience, but document the tradeoff. KeePass database/key-file and SSH host-key options are host/working-tree path strings, not Nix paths, so private material is not copied into the store.

## Paths and secret groups

`sopsRoot` is normally a Nix path such as `./secrets`. Projection uses that path, while helper commands resolve the corresponding working-tree path. Run helpers from anywhere inside the flake; the helper locates the nearest enclosing `flake.nix`. If you invoke a helper from outside the flake, use an absolute `osPath`:

```nix
sopsRoot = {
  nixPath = ./secrets;
  osPath = "/absolute/path/to/secrets";
};
```

`osPath` may start with `~`, `~/`, or `$HOME`; other shell expansion is intentionally not supported. If `osPath` is absolute, helpers may run outside the flake, but relative key-source paths then resolve from the current directory. Run inside the flake when using relative key-source paths. Plain `clusterSopsFile` and explicit `sopsFile` strings are relative to `sopsRoot`; absolute paths are allowed. Nix paths are not accepted for writable sops files.

The generated sops configuration is `<sopsRoot>/.sops.yaml`. When invoking `sops` manually, either run from `sopsRoot` or set `SOPS_CONFIG` explicitly, for example `SOPS_CONFIG=secrets/.sops.yaml sops secrets/example/cluster.yaml`.

The sops root must contain a committed `.secret-service-root` marker. Evaluation tolerates a missing marker, but mutating helpers require it. Initialize a fresh root with:

```bash
nix run .#<cluster>.secrets.secretsInitRoot
git add secrets/.secret-service-root
```

The marker contains only a random root ID, cluster names and FQDN; it is a safety guard, not a secret or authorization boundary.

A “group” in this service is a **cluster-local secret group**, not an OS user group. A cluster secret with `sopsFile = "cluster/monitoring"` is projected only to the machines listed in `groups.monitoring`. Use cluster-wide files or machine files when different access is required. A cluster template can set `sopsFile = "cluster/<group>"` to limit projection to that group; without `sopsFile`, it is projected to all selected nodes and must reference only cluster-wide secrets.

Custom `sopsFile` values participate in recipient generation. The expected recipients for a custom file are the union of the nodes that reference it, plus the admin key.

## Sync, rotate and key generation

These are separate operations:

- `secretsSyncKeyHolders` regenerates `<sopsRoot>/.sops.yaml`, updates recipients and only rotates data keys when the recipient configuration changed.
- `secretsRotate` rotates data keys for every managed sops file.
- `secretsKeyGenerate` generates or replaces a host identity.

`secretsSyncKeyHolders` and `secretsRotate` work on the discovered managed file set, not on every YAML file below `sopsRoot`. They stage changes and restore the previous files if a sops operation fails.

## Deployment

Secrets are encrypted files in the Nix store and are copied as part of the normal system closure. A `nixos-rebuild switch` or colmena deployment is the secret deployment.

First installation via `nixos-anywhere` needs the host age key before activation. The `create` package injects it through the generic `deployment.extraFiles` option, which builds a temporary `--extra-files` tree at runtime. On later deployments, `secretsInstallKey` checks or reinstalls the key over SSH; the system deployment handles secret activation.

## Rotation and recovery

There are three different operations:

1. **Decryption key holder change** — edit decryption key holders, run `sops updatekeys`, commit.
2. **Data-key rotation** — run `sops rotate`, commit.
3. **Secret-value rotation** — generate the new password/certificate/token and update the sops file with `sops set` or `sops edit`.

When removing a decryption key holder because a key may have been compromised, follow the sops-recommended order:

1. Remove the key from `<sopsRoot>/.sops.yaml`.
2. Run `sops updatekeys` on the affected files.
3. Run `sops rotate --in-place` on those files.
4. Commit the updated files.
5. Rotate the actual secret values.

This order matters: removing a decryption key holder without rotating the data key can leave the removed holder able to recover the old data key from an older version of the file and use it against the new file. Old ciphertext in Git history or the Nix store cannot be revoked by sops; rotating the actual values is what limits the impact.

See the upstream sops documentation: <https://getsops.io/docs/usage/key-management/>.

For rollback, keep the old host identity for a short window, or keep it in KeePass and install it temporarily. The admin recovery key is a decryption key holder of every sops file and is the long-term recovery path. Do not keep old keys on hosts indefinitely.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `secret ... is not valid` at build time | A declared `key` is missing from the sops file. |
| Activation cannot decrypt a file | The host public key is not a decryption key holder, or the key file is missing/wrong. Run `secretsCheck`. |
| Secret path is missing at runtime | The secret is not declared for that machine, the key is wrong, or the service started before activation. Check `sops.secrets.<name>.path` and unit ordering. |
| Service cannot read a secret | Check `owner`, `group` and `mode`; hardened units may need `ReadOnlyPaths` for `/run/secrets`. |
| VM cannot decrypt | Check the host-side per-VM key file and the microvm share mount ordering. |
| Old generation cannot boot after key rotation | The old identity was removed from the host. Restore it temporarily or use the admin recovery key. |

## Further documentation

- [`SPEC.md`](./SPEC.md) — normative option and behavior reference.
- [`DECISIONS.md`](./DECISIONS.md) — design decisions, rejected alternatives and rationale.
- [`concept.md`](./concept.md) — architecture and lifecycle overview.
