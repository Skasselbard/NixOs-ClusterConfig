# Secret Service — Decisions and Rationale

> **Status:** decision log for the implemented sops-nix secret service. This file records why the design looks the way it does, including alternatives that were considered and rejected.

## Context

The previous secret service had three parts:

1. cluster-level secret declarations with `file` and `keepass` data backends,
2. a deployment pipeline that staged secrets, encrypted them with gocryptfs, copied an archive with rsync and restarted a remote service,
3. a custom systemd service that mounted the gocryptfs archive and bind-mounted per-user directories.

The encryption key was derived from deployment metadata (`configHash`), which is not secret. That was obfuscation rather than real encryption at rest. The custom runtime and transfer pipeline also created a large maintenance and failure surface.

## Decision log

### D1 — Use sops-nix, not agenix

**Decision:** use sops-nix with age as the primary mechanism.

**Reasoning:**

- sops-nix supports per-secret owner, group, mode, path, templates, `neededForUsers`, `restartUnits` and `reloadUnits`.
- sops supports multiple key backends and key groups, which leaves room for PGP, KMS or Vault Transit later.
- The repo already manages multi-secret configuration files (Kubernetes, etcd, Vault), where sops templates are valuable.
- agenix is simpler but age-only and lacks templates and the richer lifecycle integration.

**Rejected alternative:** agenix. It remains a reasonable lightweight choice, but would require more custom glue for this repo's use cases.

### D2 — Sops is the only cluster secret backend

**Decision:** remove the `file`/`keepass` backend abstraction from the cluster secret service. All secrets are sops secrets.

**Reasoning:**

- The old backends existed to populate files on the target through a custom pipeline.
- sops-nix already owns target-side installation, permissions and lifecycle.
- Keeping a second abstraction would duplicate concepts and complicate validation.
- A future data backend (for example Vault) should be a separate module, not a new branch in the sops projection.

**Rejected alternative:** keep the old backend abstraction and use sops only for encryption. This would preserve unnecessary complexity and still require custom deployment code.

### D3 — KeePass is key escrow, not a data backend

**Decision:** KeePass stores a small number of age private keys and the admin recovery key. It does not store secret values used at runtime.

**Reasoning:**

- sops has no KeePass data backend.
- A sops key service or age plugin only manages keys; the secret values still live in sops files.
- A real KeePass data backend would require forking sops and still would not solve unattended boot on the target.
- KeePass is a good human-friendly place to escrow a handful of keys; it is not a good runtime dependency.

**Rejected alternatives:** custom sops key service, custom age plugin, sops fork with a KeePass master key. All have high cost and do not provide the desired “browse secrets in KeePass” workflow for the deployed data.

### D4 — Per-file isolation; no per-secret recipients inside one file

**Decision:** machine-private secrets go into per-machine sops files. Shared secrets go into purpose-specific cluster/group files. Do not put different trust groups into one sops file.

**Reasoning:**

- A sops file has one data key and one recipient set for the whole file.
- Key groups are alternative ways to recover the same data key, not per-secret access control.
- The file is the isolation boundary. A compromised machine can decrypt its own file and any shared file it is intentionally a recipient of, but not other machines' files.

**Rejected alternative:** one cluster-wide sops file for everything. It is simple but gives every selected machine access to every secret in the file.

### D5 — Keep the cluster config as the declaration location

**Decision:** keep secret declarations under `machines.<machine>.secrets` and add cluster-scoped declarations under `services.secrets.secrets`. Project them into `sops.secrets`.

**Reasoning:**

- The cluster config remains the place where users declare which machine gets which secret and at which path.
- The actual values remain in normal sops files.
- Projection avoids duplicating owner/mode/path declarations in every machine's native sops config.

### D6 — Use sops terminology; no aliases

**Decision:** use `sopsFile`, `key`, `name`, `path`, `owner`, `group`, `mode`, `restartUnits`, `reloadUnits`, `neededForUsers`, `format`. Do not retain `linkPath` or `permissions` aliases.

**Reasoning:**

- Direct mapping to sops-nix reduces cognitive overhead and documentation drift.
- The old names would imply behavior that no longer exists.
- This is a demo repo; a clean break is preferable to long-lived compatibility aliases.

### D7 — Per-machine sops files by default

**Decision:** default machine-scoped secrets to `<sopsRoot>/<cluster>/machines/<machine>.yaml`. Default cluster-scoped secrets to `<sopsRoot>/<cluster>/cluster.yaml`. Group files live under `<sopsRoot>/<cluster>/cluster/<group>.yaml`.

**Reasoning:**

- It gives per-machine isolation without per-secret key tuning.
- The number of files scales with machines and trust groups, not secrets.
- Cluster-scoped files are explicit and small.
- The cluster layer supports multiple clusters in one repository.

### D8 — Machine-scoped secrets override cluster-scoped secrets

**Decision:** if the same `<user>/<secret>` is defined at cluster and machine scope, the machine definition wins. Emit a Nix warning naming both definitions.

**Reasoning:**

- A machine-specific definition is more specific and usually intentional.
- A warning avoids silent shadowing.
- A hard error would make per-machine overrides unnecessarily awkward.

### D9 — Activation-script mode is the default

**Decision:** rely on sops-nix's default activation-script behavior. Do not force a custom systemd unit. Allow sops-nix to use its systemd unit automatically when `systemd.sysusers` or `userborn` is enabled.

**Reasoning:**

- The old custom unit existed mainly to maintain gocryptfs mounts and bind mounts.
- sops-nix writes secret files directly into a RAM-backed store; no long-running mount service is needed.
- Activation-script mode is the upstream default and has fewer moving parts.
- `useSystemdActivation` remains available and can be set explicitly if needed.

### D10 — Deploy secrets through the normal system closure

**Decision:** no separate secret transfer or `deploySecrets` step. Encrypted sops files are part of the system closure and are deployed by `nixos-rebuild switch` or colmena. Activation decrypts them on the target.

**Reasoning:**

- The encrypted file is safe in the Nix store.
- The normal deployment already handles closure transfer and activation ordering.
- It removes the rsync, remote metadata, restart and archive-management code.
- First install needs the age key before activation; `nixos-anywhere --extra-files` handles that.

### D11 — Dedicated age keys by default; support SSH and native backends

**Decision:** default recommendation is a dedicated age key per node. Support KeePass, age-key files, SSH host key and native sops configuration. Do not force one key model.

**Reasoning:**

- Dedicated keys separate secret access from SSH access, rotate independently and are easy to escrow.
- SSH keys are convenient and can avoid bootstrap, but couple secret access to remote access and require re-encryption when host keys change.
- Native configuration keeps the door open for PGP, KMS, Vault Transit and age plugins.

### D12 — Key rotation and rollback

**Decision:** keep old identities for a bounded rollback window, or keep them in KeePass and install temporarily. Do not keep old keys on hosts indefinitely. Always include an admin recovery key in every file.

**Reasoning:**

- Old NixOS generations reference old sops files; the age key file is mutable state outside the generation.
- Replacing the key immediately can make rollback fail.
- Keeping old keys forever increases exposure, especially for keys rotated after suspected compromise.
- The admin key is the long-term recovery path.

### D13 — Sops removal policy: updatekeys + rotate + rotate values

**Decision:** when removing a recipient because a key may be compromised, remove it from `.sops.yaml`, run `sops updatekeys`, then `sops rotate --in-place`, commit, and only then rotate the actual secret values.

**Reasoning:**

- `sops updatekeys` alone does not revoke access if the removed holder previously had the data key; they can recover it from an old file version and use it against the new file if the data key is unchanged.
- `sops rotate` changes the data key so old holders cannot decrypt the new file.
- Old ciphertext in Git history or the Nix store remains decryptable by the old key; rotating the actual values is the only way to limit the impact.

**Reference:** <https://getsops.io/docs/usage/key-management/>

### D15 — Parameterless commands

**Decision:** commands are generated per machine/cluster with all parameters embedded. Use separate commands for separate operations: `secretsCheck`, `secretsInstallKey`, `secretsSyncKeyHolders`, `secretsRotate`, plus the `secretEdit`, `secretSet`, `secretUpdateKeys` and `secretRotate` helpers.

**Reasoning:**

- The cluster config already knows the target, key source, sops files and paths.
- Parameterless commands are harder to misuse and easier to call from CI.
- Different operations have different side effects and should not be overloaded behind flags.

### D16 — Templates use function-valued content

**Decision:** cluster/machine template `content` is a function evaluated with the NixOS `config`, e.g. `{ config }: ''...${config.sops.placeholder...}...''`.

**Reasoning:**

- Placeholders live in the NixOS module context, not in cluster config context.
- Using the evaluated `clusterConfig` or `self.nixosConfigurations` from inside the same evaluation risks self-reference or stale passes.
- A function is explicit and avoids magic placeholder rewriting.

### D17 — `neededForUsers` is a special projection case

**Decision:** when `neededForUsers = true`, force root ownership and the early sops path; the logical cluster `<user>` is not the runtime owner.

**Reasoning:**

- sops-nix installs these secrets before users exist.
- They are intended for `hashedPasswordFile` and similar early user setup.
- Treating them like normal user-owned files would fail at activation.

### D18 — VMs get their own keys

**Decision:** each microVM gets a dedicated age key, exposed through a per-VM host share. VMs do not share host secrets.

**Reasoning:**

- Machine isolation should extend to VMs.
- The host controls the VM and therefore has access to its key, but one VM should not be able to read another VM's secrets.
- A share is the least invasive mechanism for the current microvm backend.

**Open implementation detail:** verify share mount ordering and guest permissions before sops activation.

### D19 — Generate `.sops.yaml`, not secret values

**Decision:** generate `.sops.yaml` from cluster public keys, admin key and shared groups. Do not generate secret contents in the secret service; domain modules do that.

**Reasoning:**

- `.sops.yaml` is derivable from public configuration.
- Secret values require plaintext or domain knowledge (for example, TLS certificates with SANs).
- Automating derivable files reduces user error; inventing domain-specific secrets does not belong in a generic secret service.

### D20 — Certificates and Vault data backends are out of scope

**Decision:** certificate generation and a Vault data backend are not part of the secret service.

**Reasoning:**

- Certificate lifecycle belongs to certificate tooling (the existing certificate module, cert-manager or Vault PKI).
- sops supports Vault as a key backend (Transit), not as a data backend.
- A true Vault data backend would be a separate module with runtime fetching and policy, not a branch in the sops projection.

### D21 — `secret*` helper packages

**Decision:** provide `secretEdit`, `secretSet`, `secretUpdateKeys` and `secretRotate` packages that operate on the resolved default sops files, plus `secret<Group>Edit`, `secret<Group>Set`, `secret<Group>UpdateKeys` and `secret<Group>Rotate` for each configured group. Use `secret*` naming, not `sops*`.

**Reasoning:**

- Editing the correct sops file is easy to get wrong, especially when machine and cluster files are both in play.
- Embedding the resolved file path in the package removes a class of operator mistakes.
- Thin wrappers keep the normal sops workflow without hiding the underlying commands.

### D22 — No Git status checks

**Decision:** the service does not check whether sops files are tracked or dirty. sops works on file paths and does not require Git state; the helper commands only report changed files.

**Reasoning:**

- sops-nix itself does not perform Git checks.
- The checks added complexity and depended on how the helper command was launched.
- Git-backed flakes still require files to be tracked to be visible to Nix; that is a Nix constraint, not a service feature.

### D23 — Secret groups filter projection

**Decision:** cluster-local secret groups are access groups. A cluster secret using `sopsFile = "cluster/<group>"` is projected only to machines in that group, not to every selected machine.

**Reasoning:**

- A group file is only decryptable by its members and the admin key.
- Projecting it to non-members creates a deployment that fails activation for no useful reason.
- Secret groups are unrelated to OS users/groups.

### D24 — File-recipient map instead of path patterns only

**Decision:** derive recipients from the actual files referenced by secrets and the default machine/group/cluster files. Generate one rule per resolved file.

**Reasoning:**

- `clusterSopsFile` and explicit `sopsFile` paths must work.
- Multiple nodes can reference the same custom file; the recipient set is their union plus admin.
- It avoids processing unrelated files found by `find`.

### D25 — Sync and rotate are separate

**Decision:** `secretsSyncKeyHolders` updates recipients and rotates data keys only when the recipient configuration changed. `secretsRotate` rotates all managed files unconditionally.

**Reasoning:**

- `sops updatekeys` does not change the data key.
- Rotating after recipient removal is important for compromise recovery.
- Unconditional rotation should be an explicit operation.

### D26 — Native sources are manually managed

**Decision:** native sources are skipped by sync unless a manual public key is configured. Native PGP/KMS/Vault creation rules are outside this service.

**Reasoning:**

- The service cannot derive those recipients from private cluster config.
- Silently omitting a required recipient would produce a broken or insecure `.sops.yaml`.

### D27 — Path roots and working-tree resolution

**Decision:** `sopsRoot` is a Nix path by default (`./secrets`), with an optional explicit `{ nixPath, osPath }` form. Helper commands derive the working-tree path from the store suffix and Git flake prefix, or use `osPath`. Helpers may run from any directory inside the flake; the nearest enclosing `flake.nix` is used as the flake root. Writable sops paths are strings; Nix paths are not accepted for writable `sopsFile` values.

**Reasoning:**

- Nix paths point at the immutable store.
- Projection and helper commands need one consistent path model.
- Absolute paths remain possible for external secret trees.

### D28 — Stage destructive updates

**Decision:** sync and rotate back up managed files and restore them if a sops operation fails. `.sops.yaml` is written to a temporary file and moved into place only after success.

**Reasoning:**

- A partial key update leaves the repository in an inconsistent state.
- Backup and restore are simpler and safer than trying to continue after a sops failure.

### D29 — Exact target key and recipient verification

**Decision:** `secretsCheck` reads the target key, derives its public key and requires an exact match. It also compares the complete age recipient set against the expected set. `secretsInstallKey` verifies the installed key by reading it back.

**Reasoning:**

- Checking only that a key file exists does not prove it is usable.
- Checking only that the expected key is present does not detect an extra recipient.

### D30 — Root marker and bootstrap

**Decision:** store a non-secret `.secret-service-root` marker in the sops root. Evaluation tolerates a missing marker; mutating helpers require it. `secretsInitRoot` creates it during setup.

**Reasoning:**

- Mutable secret files cannot be compared safely.
- The marker identifies the intended secret root without storing secret data.
- A missing marker must not block evaluation, or the initializer could never be built.
- Committing the marker makes it part of the evaluated store snapshot.

### D31 — Remove `secretsRemoveOld`

**Decision:** do not provide a separate old-identity removal command. `secretsInstallKey` replaces the target key file contents with the current identity.

**Reasoning:**

- The target key is a single managed file, not a set of generations.
- Reinstallation already removes old contents from that file.
- KeePass history is not host identity state and is not managed by this command.

## Rejected alternatives

| Alternative | Why rejected |
|---|---|
| Keep gocryptfs + custom systemd unit | Weak derived key, large custom surface, unnecessary mount lifecycle. |
| agenix | Simpler, but age-only and fewer lifecycle/templates features. |
| KeePass data backend via sops plugin | No data-backend plugin mechanism; key service is closed and sops-nix does not use it; fork cost is high. |
| Custom age plugin backed by KeePass | Only manages keys, not values; target boot would need KeePass DB/password; circular and complex. |
| One cluster-wide sops file | Gives every machine access to every secret. |
| Per-secret recipients inside one file | Not supported by sops; the file is the isolation boundary. |
| Auto-commit sops changes after key-holder synchronization | Too easy to commit unintended secrets; explicit commit is safer. |

## Open items and future work

- MicroVM share ordering and permission verification.
- Backend-specific `.sops.yaml` generation for PGP/KMS/Vault.
- Runtime credential checks for Vault/KMS in `secretsCheck`.
- Optional per-generation key file paths for stronger rollback isolation.
- Home-manager secret module for per-user secrets, if needed.

## Security notes

- Every sops file should include an admin recovery key holder.
- Protect and back up the admin key; its compromise compromises all files.
- Machine-private files must not contain other machines' public keys.
- Old keys on hosts are a bounded rollback convenience, not a permanent design.
- Old ciphertext cannot be revoked; rotate values after key compromise.
- `sops.environment` must not contain secret values.
- Do not put plaintext secrets in the Nix store, generated scripts or command-line arguments.
