# Secret Service

> **Status:** this document describes the target sops-nix-based design. The current code in this directory still contains the previous gocryptfs-based implementation while the migration is in progress. `SPEC.md` is the normative option and behavior reference; `DECISIONS.md` records why the design looks the way it does.

The secret service lets you declare secrets in the cluster configuration and have them installed on the correct target nodes with the correct owner, group, mode and path.

It uses [sops-nix](https://github.com/Mic92/sops-nix) for the runtime side and normal sops files for storage.

## What it gives you

- Secrets are declared in defined placeholders: the cluster configuration under `machines.<machine>.secrets` and `services.secrets.secrets`.
- Secret values live in ordinary sops files, usually committed to the repository in encrypted form.
- Each machine has its own sops file by default, so a compromised machine cannot decrypt another machine's secrets.
- Secrets are decrypted on the target at activation time and written to a RAM-backed secret store.
- Per-secret `owner`, `group`, `mode`, `path`, `restartUnits` and `reloadUnits` are supported.
- Templates can render configuration files from several secrets.
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

A random **data key** encrypts the values. The data key is itself encrypted to one or more **recipients**. Anyone with a matching identity can decrypt the file.

`.sops.yaml` decides which recipients are used for which file. `sops edit`, `sops set`, `sops updatekeys` and `sops rotate` are the normal editing and key-management tools.

sops-nix reads `sops.secrets` declarations from the NixOS configuration, builds a manifest, and during activation runs `sops-install-secrets`. That helper decrypts each secret, writes the real file into a RAM-backed directory, applies ownership and permissions, creates symlinks at the configured paths, and restarts configured units. The plaintext never goes into the Nix store.

## Default file layout

```text
secrets/
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

## Quick start

### 1. Enable the service

```nix
services.secrets = {
  selectors = [ filters.clusterMachines ];

  sopsRoot = ./secrets;
  machinesDir = "machines";
  clusterDir = "cluster";

  # Used by secretsSyncRecipients to generate .sops.yaml.
  adminPublicKey = "age1...";

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
      entry = "hosts/vm1";
      attachment = "age.key";
      # Optional: avoid an interactive prompt in automation
      # passwordCommand = "...";
    };
    publicKey = "age1...";
  };
};
```

Supported key-source types are `age`, `keepass`, `file`, `ssh` and `native`. `native` means you configure `sops.*` yourself, for example PGP, KMS, Vault or age plugins.

### 3. Generate or update `.sops.yaml`

```bash
nix run .#example.secrets.secretsSyncRecipients
```

This derives `.sops.yaml` from the machine public keys, the admin key and the configured groups. It also runs `sops updatekeys` and, where recipients were removed, `sops rotate`. Commit the resulting files before deploying.

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
nix run .#example.vm1.secretsUpdate
```

`secretsCheck` is read-only. `secretsUpdate` installs/verifies the host key, verifies the sops files, and deploys the machine. Secrets are part of the normal system closure, so there is no separate secret-transfer step.

## Commands

Most commands are parameterless. Everything they need is embedded at Nix evaluation time. `secretSet` is the exception: it takes `--key` and reads the value from stdin.

| Command | Purpose |
|---|---|
| `nix run .#<clusterName>.<machineName>.secretsCheck` | Read-only verification of the key, recipients, declared secrets and templates. |
| `nix run .#<clusterName>.<machineName>.secretsUpdate` | Ensure the host key, verify everything, and deploy the machine. |
| `nix run .#<clusterName>.<machineName>.secretsRemoveOld` | Remove old age identities from the host after the rollback window. |
| `nix run .#<clusterName>.<machineName>.secretEdit` | Edit the machine's default sops file. |
| `nix run .#<clusterName>.<machineName>.secretSet -- --key <user>/<secret>` | Set one machine secret from stdin. |
| `nix run .#<clusterName>.secrets.secretsSyncRecipients` | Regenerate `.sops.yaml` from the cluster configuration, run `sops updatekeys`, and rotate data keys when recipients are removed. |
| `nix run .#<clusterName>.secrets.secretEdit` | Edit the cluster sops file. |
| `nix run .#<clusterName>.secrets.secretSet -- --key <user>/<secret>` | Set one cluster secret from stdin. |
| `nix run .#<clusterName>.secrets.secretUpdateKeys` | Run `sops updatekeys` on the cluster files. |
| `nix run .#<clusterName>.secrets.secretRotate` | Run `sops rotate` on the cluster files. |

The package path determines the scope: machine commands live under `<clusterName>.<machineName>`, cluster commands under `<clusterName>.secrets`.

`secretsUpdate` refuses to run when sops files are untracked or dirty. For development only, the dirty check can be bypassed by passing a flag to the script:

```bash
nix run .#example.vm1.secretsUpdate -- --impure
```

Do not confuse this with Nix's own `--impure`.

## Key sources

| Type | Behavior |
|---|---|
| `age` | A dedicated age key file on the target, normally `/var/lib/sops-nix/key.txt`. |
| `keepass` | The helper extracts the age key from a KeePass entry during setup/recovery. KeePass is not needed at boot. |
| `file` | A securely stored local key file is installed on the target during setup. |
| `ssh` | The target's SSH host key is used as the age identity. No key injection is needed, but the host key must exist before activation and reimaging requires re-encryption. |
| `native` | You configure `sops.age.*`, `sops.gnupg.*`, `sops.environment` or age plugins directly. |

Dedicated age keys are the default recommendation because they rotate independently from SSH access and have a clear recovery path. SSH keys are supported for convenience, but document the tradeoff.

## Deployment

Secrets are encrypted files in the Nix store and are copied as part of the normal system closure. A `nixos-rebuild switch` or colmena deployment is the secret deployment.

First installation via `nixos-anywhere` needs the host age key before activation. The `create` package injects it with `--extra-files` and verifies the public key before installing. On later deployments, `secretsUpdate` checks or reinstalls the key over SSH.

## Rotation and recovery

There are three different operations:

1. **Recipient/key change** — edit recipients, run `sops updatekeys`, commit.
2. **Data-key rotation** — run `sops rotate`, commit.
3. **Secret-value rotation** — generate the new password/certificate/token and update the sops file with `sops set` or `sops edit`.

When removing a recipient because a key may have been compromised, follow the sops-recommended order:

1. Remove the key from `.sops.yaml`.
2. Run `sops updatekeys` on the affected files.
3. Run `sops rotate --in-place` on those files.
4. Commit the updated files.
5. Rotate the actual secret values.

This order matters: removing a recipient without rotating the data key can leave the removed holder able to recover the old data key from an older version of the file and use it against the new file. Old ciphertext in Git history or the Nix store cannot be revoked by sops; rotating the actual values is what limits the impact.

See the upstream sops documentation: <https://getsops.io/docs/usage/key-management/>.

For rollback, keep the old host identity for a short window, or keep it in KeePass and install it temporarily. The admin recovery key is a recipient of every sops file and is the long-term recovery path. Do not keep old keys on hosts indefinitely.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `secret ... is not valid` at build time | A declared `key` is missing from the sops file. |
| Activation cannot decrypt a file | The host public key is not a recipient, or the key file is missing/wrong. Run `secretsCheck`. |
| `secretsUpdate` refuses to run | Sops files are untracked or dirty. Commit them or use the documented development bypass. |
| Secret path is missing at runtime | The secret is not declared for that machine, the key is wrong, or the service started before activation. Check `sops.secrets.<name>.path` and unit ordering. |
| Service cannot read a secret | Check `owner`, `group` and `mode`; hardened units may need `ReadOnlyPaths` for `/run/secrets`. |
| VM cannot decrypt | Check the host-side per-VM key file and the microvm share mount ordering. |
| Old generation cannot boot after key rotation | The old identity was removed from the host. Restore it temporarily or use the admin recovery key. |

## Further documentation

- [`SPEC.md`](./SPEC.md) — normative option and behavior reference.
- [`DECISIONS.md`](./DECISIONS.md) — design decisions, rejected alternatives and rationale.
- [`concept.md`](./concept.md) — architecture and lifecycle overview.
