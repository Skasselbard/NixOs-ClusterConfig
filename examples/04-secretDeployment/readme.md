# Secret Deployment Example

Deploy encrypted secret files to cluster machines using the `secret-service` module. Secrets are encrypted at rest and never stored in the publicly readable Nix store.

## What You Will Learn

- How to enable and configure the `secret-service` cluster service
- How to define secrets per machine, per user, and per backend
- How to use both the `file` and `keepass` backends
- The two-step deployment workflow: system config + secrets
- How secrets are encrypted, transferred, and mounted on the target machine

## Prerequisites

- Three VMs already deployed from [Example 01](../01-simpleCluster/)
- The SSH private key added to your SSH agent:

  ```bash
  ssh-add ../00-exampleConfigs/secrets/sshKey
  ```

## How the Secret Service Works

The secret-service module handles the full lifecycle of secret management:

1. **Build/deploy time:** Reads secret content from the configured backend on the machine that runs `deploySecrets`
2. **Deployment:** Encrypts all staged secrets into a [gocryptfs](https://nuetzlich.net/gocryptfs/) archive and copies it to the target
3. **Runtime:** A systemd service on the target decrypts the archive and bind-mounts secrets with per-user file permissions

Secrets never appear in the Nix store. They are encrypted during transfer and decrypted only in memory (via tmpfs/shm).

### Secret definition structure

Secrets are defined per machine in the cluster config:

```nix
secrets = {
  <user>.<backend> = {
    <secretName> = {
      backendPath = "<local-path>";   # Path to the file on the BUILD machine
      # Optional:
      # linkPath = "/path/on/remote";  # Symlink location on the target (read-only)
      # permissions = "400";           # File permissions (default: owner-read-only)
    };
  };
};
```

- **`<user>`** — The system user who will own the secret. Must exist on the target machine (either as a cluster user or defined in nixosModules).
- **`<backend>`** — The retrieval backend. This example uses both `file` and `keepass`.
- **`backendPath`** — Backend-specific identifier. For `file`, it is a local file path on the deployment machine. For `keepass`, it is the entry path inside the KeePass database.

### Backend-specific notes

- **`file` backend**
  - Reads a plain local file during `deploySecrets`.
  - Use a string path outside the Nix store for real secrets.
  - Prefer absolute paths without spaces.
- **`keepass` backend**
  - Unlocks one KeePass database and reads all requested entries in one batch.
  - Supports `content = "password"` and `content = "attachment"`.
  - Uses `attachmentName` when an entry contains multiple attachments.

## Configuration in This Example

| Machine | Secrets | Description |
| --- | --- | --- |
| vm0 | `testService.file.testSecret` | A secret for the `testService` system user (defined inline in nixosModules) |
| vm0 | `admin.file.adminSecret` | A secret for the `admin` cluster user |
| vm1 | `admin.keepass.testPassword` | Reads the KeePass password field from `04-secretDeployment/TestPassword` |
| vm1 | `admin.keepass.attachment` | Reads the only attachment from `04-secretDeployment/TestAttachment` |
| vm1 | `admin.keepass.login` | Reads the `Login.txt` attachment from a multi-attachment entry |
| vm1 | `admin.keepass.personalData` | Reads the `PersonalData.txt` attachment from a multi-attachment entry |
| vm2 | (none) | No secrets defined — still gets the service module but deployment remains a no-op |

The example therefore shows both supported backends in one cluster:

- `vm0` demonstrates the `file` backend.
- `vm1` demonstrates the `keepass` backend.
- `vm2` shows that the service can be enabled on a machine without any secrets.

## Deployment

### Step 1: Deploy the system configuration

The system config includes the secret-service systemd unit, the `secret-service` user, and gocryptfs.

```bash
nix run .#colmena apply
```

Or deploy individually:

```bash
nix run .#example.vm0.deploy
nix run .#example.vm1.deploy
nix run .#example.vm2.deploy
```

### Step 2: Deploy the secrets

Secret deployment is a separate step because secrets are not part of the NixOS configuration (they bypass the Nix store).

```bash
nix run .#example.vm0.deploySecrets
nix run .#example.vm1.deploySecrets
nix run .#example.vm2.deploySecrets
```

Or use the helper scripts:

```bash
bash deploy.sh          # System configuration
bash deploySecrets.sh   # Secrets
```

> **Note:** The `deploySecrets` command validates that all referenced secret files exist and are readable before encrypting and transferring them.

For the KeePass backend, deployment also validates that:

- the database can be opened,
- the configured entry exists, and
- the requested password field or attachment is present.

## Test

1. SSH into vm0:

   ```bash
   ssh root@192.168.122.200
   ```

2. Check that secrets are mounted for the `testService` user:

   ```bash
   ls -la /dev/shm/nixos-secret-service/testService/
   ```

3. Check that secrets are mounted for the `admin` user:

   ```bash
   ls -la /dev/shm/nixos-secret-service/admin/
   ```

4. Verify the secret-service systemd unit is running:

   ```bash
   systemctl status secret-service
   ```

5. SSH into vm1 and inspect the linked KeePass-backed secrets:

  ```bash
  ssh root@192.168.122.201
  ls -la /home/admin/secrets
  sudo -u admin cat /home/admin/secrets/testPassword
  ```

## Important Considerations

- **The `file` backend paths must exist** on the machine where you run `deploySecrets`. The command will fail with a validation error if they do not.
- **Do not use Nix paths for real `file` backend secrets.** If Nix sees a plain file as a path value, it will copy it into the store, which makes it publicly readable.
- **The `file` backend currently expects simple local paths.** Prefer absolute paths without spaces or shell-style expansions.
- **The KeePass database may be a Nix path** as the `.kdbx` file is already encrypted, as shown in this example.
<!-- - **Secrets are re-deployed independently** from system configuration. After changing secrets, you only need to run `deploySecrets` again. -->
<!-- - **The `secret-service` user** is created automatically by the module. It manages the encrypted archive and decryption. -->
- **Permissions** default to `400` (owner-read-only). Customize with the `permissions` option per secret.

## Notes

- Password for the KeePass database used in this example: `exampledb`