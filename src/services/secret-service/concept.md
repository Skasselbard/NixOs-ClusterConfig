# Secret Service — Architecture and Lifecycle

> This is a short conceptual overview. The normative option reference is in [`SPEC.md`](./SPEC.md); the rationale is in [`DECISIONS.md`](./DECISIONS.md); the user guide is [`Readme.md`](./Readme.md).

## Components

```text
cluster configuration
  services.secrets.secrets.<user>.<secret>      (cluster scope)
  machines.<machine>.secrets.<user>.<secret>     (machine scope)
  services.secrets.templates / machine templates
            |
            |  Nix evaluation: projection
            v
  sops.secrets / sops.templates declarations
            |
            |  normal system closure
            v
  encrypted sops files in the Nix store
            |
            |  activation on the target
            v
  sops-install-secrets
    - decrypts with the host identity
    - writes real files into a RAM-backed store
    - applies owner/group/mode
    - creates symlinks at the configured paths
    - restarts/reloads units when values change
```

## Sources of truth

| Data | Source of truth |
|---|---|
| Which secret belongs to which machine/user and where it is mounted | cluster configuration |
| Secret values | sops files |
| Which keys can decrypt a sops file | `.sops.yaml` and the sops file metadata |
| Host identities | key source configuration (KeePass, age key file, SSH key or native sops configuration) |
| Recovery key | KeePass or another protected escrow |

The secret service never stores plaintext secret values in the Nix store or in generated scripts.

## Isolation model

- A sops file has one data key and one decryption key holder set. The file is the isolation boundary.
- Machine-private secrets live in the machine's sops file, encrypted to that machine and the admin recovery key.
- Shared secrets live in a cluster or secret-group file, encrypted only to the machines that need them and the admin key. Secret groups are cluster-local access groups, not OS groups.
- The sops root carries a committed `.secret-service-root` marker so helpers can verify the working-tree root before editing.
- A compromised machine can read its own file and any shared file it is intentionally a key holder of. It cannot read another machine's private file.

## Lifecycle

### Provisioning a new machine

1. Generate a dedicated age key, or select SSH/native key source.
2. Store the public key in the cluster configuration/`.sops.yaml`; store the private key in KeePass, an age-key file, or on the host depending on the key source.
3. The `create` package injects the age key with `nixos-anywhere --extra-files` before activation.
4. The sops file was already encrypted to the host's public key.
5. Activation decrypts it and installs the secrets.

### Changing a secret value

1. Edit the sops file with `nix run .#<clusterName>.<machineName>.secretEdit` or set one value with `nix run .#<clusterName>.<machineName>.secretSet -- --key <user>/<secret>`.
2. Commit the encrypted file.
3. Deploy the machine normally. Run `nix run .#<clusterName>.<machineName>.secretsInstallKey` only to install or repair the host key.

### Adding or removing a machine

1. Update the machine public keys / shared groups in the cluster configuration.
2. Run `nix run .#<clusterName>.secrets.secretsSyncKeyHolders`.
   - regenerates/validates `.sops.yaml`,
   - runs `sops updatekeys`,
   - runs `sops rotate` when the recipient configuration changed,
   - reports files to commit.
3. Commit the updated files.
4. Deploy the affected machines normally; run `secretsInstallKey` only if their host key needs repair.

### Rotation and compromise

- Changing a key holder is not enough after a key compromise: the removed holder may have had the old data key. Run `sops updatekeys`, then `sops rotate`, then rotate the actual secret values.
- Old ciphertext in Git history or the Nix store cannot be revoked by sops. Rotating the actual values limits the impact.
- Keep old host identities only for a bounded rollback window, or in KeePass for temporary recovery.
- The admin recovery key is included in every file as the long-term fallback.

## Target activation

sops-nix uses a NixOS activation script by default. It can use a oneshot systemd unit when `useSystemdActivation` is enabled or when sysusers/userborn is active. There is no long-running mount service: the real secret files live in a RAM-backed directory and are exposed through symlinks at the configured paths.

## VMs

MicroVMs are deployed with their host and do not have individual deployment commands. Each VM gets its own age key under a host-side per-VM path, exposed to the guest through a microvm share. The host necessarily has access to VM keys because it controls the VM; the isolation goal is between VMs, not from the host.

## Non-goals

- Generating secret values based on the config.
