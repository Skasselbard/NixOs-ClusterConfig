# Secret-Service Cluster Module
## Overview

`clusterModule.nix` implements the deployment side of the secret-service. It:

- generates `deploy-secrets.sh` to read secrets from configured backends, encrypt them with `gocryptfs`, and copy the archive to the target machine,
- generates `connect-secrets.sh` to try common SSH users automatically, and
- registers backend options for both `file` and `keepass` secrets.

---

## Deployment Flow

These steps happen during deployment:

1. **Collect machine secrets**
   - Reads `clusterConfig.clusters.this.machines.<machine>.secrets.<user>.<backend>.<secret>`.

2. **Prepare and validate each backend once**
   - Runs one prepare step per used backend.
   - Runs one validation step per used backend for the full batch of requested secrets.
   - Aborts the deployment if validation fails.

3. **Stage and encrypt secrets**
   - Retrieves all requested secrets into a temporary staging directory.
   - Generates deployment metadata and derives an encryption key from it.
   - Initializes a `gocryptfs` archive and writes the staged files into it.

4. **Transfer the encrypted payload**
   - Copies `secrets.enc` via `rsync`.
   - Writes `deployment-info.json` to the remote machine.

5. **Restart the runtime service**
   - Restarts the remote `secret-service` systemd unit after the transfer succeeds.

---

## Configuration Overview

### 1. Deployment options

- `services.secrets.deployment.tempPath` defaults to `/dev/shm/nixos-secret-service` and stores secrets in RAM before encryption.
- `services.secrets.deployment.persistentPath` defaults to `/var/lib/nixos-secret-service` and stores the encrypted payload on the remote machine.
- `services.secrets.deployment.database.fileName` defaults to `secrets.enc`.
- `services.secrets.deployment.metadata.fileName` defaults to `deployment-info.json`.

<!-- ### **2. Backend Configuration**
| Option | Description |
|--------|-------------|
| `services.secrets.backends.<backend>.retrieveSecretCommand` | Retrieves a secret. |
| `services.secrets.backends.<backend>.validateSecretCommand` | Validates a secret’s existence & permissions. | -->

### 2. Backend highlights
- `file`: Reads a local file directly. `backendPath` is a local file path on the deployment machine.
- `keepass`: Reads a local KeePass `.kdbx` database through the Rust helper CLI in `keepass-cli/`.
- `keepass backendPath`: Uses an entry path in the form `group/subgroup/entry`.
- `keepass content`: `attachment` deploys one attachment and `password` deploys the KeePass password field.
- `keepass attachmentName`: Selects one attachment when an entry contains multiple attachments.
- `keepass passwordCommand`: Can populate `SECRET_SERVICE_KEEPASS_PASSWORD` for non-interactive deployments.
- `keepass databasePath`: Currently accepts either a string path or a Nix path.

Deployment treats every backend as a batch: each used backend is prepared once, validated once, and retrieved once for the full set of configured secrets assigned to it.

KeePass deployments stream one JSON batch payload to the helper over stdin for validation and reading. The batched read returns base64-encoded secret bytes, and the deployment script materializes the files in the staging directory before encryption.

### 3. Current limitations
- `file.backendPath` is treated as a runtime string path on the deployment machine, not as a Nix-managed path. Keep it as a string literal in configuration, not a Nix path value that should be copied into the store.
- Because the path is consumed by generated shell scripts, the safest form today is a plain absolute path such as `/home/tom/secrets/example.pem`.
- Paths containing spaces are not handled reliably by the current `file` backend implementation. Prefer paths without spaces.

### 4. KeePass example

```nix
{
   clusterConfig.clusters.this.services.secrets.backends.keepass = {
      databasePath = "/home/tom/secrets/shared.kdbx";
      passwordCommand = "${pkgs.coreutils}/bin/cat /run/secrets/keepass-password";
   };

   clusterConfig.clusters.this.machines.node1.secrets = {
      nginx.keepass = {
         tls-cert = {
            backendPath = "infra/prod/nginx";
            content = "attachment";
            attachmentName = "tls.crt";
            linkPath = "/var/lib/nginx/tls.crt";
            permissions = "440";
         };
         tls-key = {
            backendPath = "infra/prod/nginx";
            content = "attachment";
            attachmentName = "tls.key";
            linkPath = "/var/lib/nginx/tls.key";
         };
         basic-auth = {
            backendPath = "infra/prod/nginx-basic-auth";
            content = "password";
            linkPath = "/var/lib/nginx/basic-auth";
         };
      };
   };
}
```

During deployment, only the secrets referenced by the machine configuration are read from KeePass, staged into the temporary deployment directory, encrypted with `gocryptfs`, and copied to the remote host.

---

## Deployment workflow

1. Add the module to your cluster configuration.
2. Deploy the machine configuration so the `secret-service` unit exists on the target.
3. Run `nix run .#<cluster>.<machine>.deploySecrets` from the flake that defines the machine.
4. Re-run `deploySecrets` whenever backend content changes.

---



# Secret-Service Nixos-Module

## Runtime service overview

The NixOS module on the remote machine is responsible for:
- **Decrypting the received archive** (`secrets.enc`).
- **Mounting secrets dynamically** using `gocryptfs`.
- **Providing access to secrets per user**.

---

## Runtime service flow

The runtime logic lives in the `secret-service` systemd service.

1. **Mount the encrypted archive**
   - Retrieves the **encryption key** from metadata.
   - Uses `gocryptfs` to **decrypt the archive in RAM** (`/dev/shm/nixos-secret-service`).

2. **Create bind mounts per user**
   - Reads the machine's configured user secrets.
   - Creates read-only bind mounts at `${tmpPath}/<user>`.
   - Applies per-secret ownership and file permissions before mounting.
   - Creates optional symlinks for secrets that define `linkPath`.

3. **Handle cleanup**
   - Secrets are **unmounted on service stop**.
   - Managed symlinks are removed before unmounting.

---

## Runtime module configuration

### 1. Deployment paths

- `services.secrets.deployment.persistentPath` defaults to `/var/lib/nixos-secret-service` and stores the encrypted archive.
- `services.secrets.deployment.tempPath` defaults to `/dev/shm/nixos-secret-service` and stores the decrypted mount in RAM.

<!-- ### **2. Encryption Configuration**
| Option | Default | Description |
|--------|---------|-------------|
| `services.secrets.deriveEncryptionKey` | `jq .configHash | sha256sum | awk '{print $1}'` | Generates encryption key. | -->

---

## Example workflow

1. Deploy machine configuration.
2. Deploy secrets with `deploySecrets` or `connect-secrets.sh`.
3. Let the remote `secret-service` unit decrypt and mount the archive.
4. Access the bind-mounted or linked secrets as the target user.
5. Stop the service to unmount the archive and remove the managed links.
