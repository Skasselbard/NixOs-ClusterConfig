# Secret Management for NixOS Deployments

## Overview

Secret management in this module means defining secrets in a backend, deploying them to a machine in encrypted form, and making them available to the correct local users at runtime.

### Phases
1. **Secret Definition**: Configuration of secrets in the secret store and machine users.
2. **Machine Deployment**: Secure transfer of secrets to remote machines.
3. **User Deployment**: Distribution and setup of secrets for specific users or services.
4. **Secret Usage**: Secure access to secrets by services or users.

---

## Components

1. **Secret Store (Backend)**: The source of truth for the secret, for example a local file or a KeePass database.
2. **Machine Deployment Script**: Reads backend content, encrypts it, and copies the result to the remote machine.
3. **Runtime Systemd Service**: Decrypts the archive and exposes secrets to the correct local users.
4. **Secret Access Path**: The mounted file or optional symlink that services and users consume.

---

## Deployment Phases

### Phase 1: Secret Definition
- Secrets are manually created in the secret store by a **local user**.
- Cluster configuration defines target users and associates them with secrets.
- For the KeePass backend, `backendPath` maps to the KeePass entry path.
- KeePass secrets can deploy either the entry password or one attachment.
- For the file backend, `backendPath` is a local file path on the deployment machine.

### Phase 2: Machine Deployment
- Secrets are transferred from the local machine to remote machines by a **deployment user**.
- Credentials for the secret store are requested at runtime.
- Secrets are validated per backend in batches, and deployment halts on errors.
- Secrets are first staged in a temporary local directory and then stored in encrypted form on the remote machine at `/var/lib/nixos-secret-service/` by default.
- Secrets will be overwritten on redeployment.
- Access to the central location on the remote machine is restricted to the **secret service user**.

### Phase 3: User Deployment
- Secrets are distributed on the remote machine by the **secret service user** using a systemd service.
- Secrets are decrypted to `${tmpPath}/mount` and then bind-mounted to `/dev/shm/nixos-secret-service/${user}` by default.
- Additional, outdated bind mounts are removed.
- Per-secret ownership is assigned to the target user and the `secret-service` group.
- Optional `linkPath` values create managed symlinks for easier consumption by services.

### Phase 4: Secret Usage
- Secrets are accessed by a **service account** or **user account** as regular files after the runtime service has mounted them.
- Access is controlled through file ownership, file permissions, and read-only bind mounts.

---

## Supported Backends

### Common Settings
- **Backend Path**:
  - Identifies the secret in the backend.

#### Validations
- The remote is accessible.
- Target directories exist or can be created.
- Each used backend is prepared once, validated once, and retrieved once for all configured secrets belonging to that backend.

### Backend Types

#### 1. **Files**
Secrets are stored in local files on the deployment machine.

- **Secret Store**: File location on disk.
- **Secret Settings**:
  - Local file path.
- **Validations**:
  - The file is accessible.
- **Current limitation**:
  - The backend currently expects simple shell-safe local paths. Prefer absolute paths without spaces or shell-style expansions.

#### 2. **KeePass**
Secrets are stored in a local `.kdbx` file.
Secrets are extracted during deployment and staged into the temporary deployment directory before encryption and transfer to the remote machine.

- **Secret Store**: `.kdbx` database.
- **Global Settings**:
  - Path to the `.kdbx` file.
  - Optional password file.
  - Optional password command for automation.
  - Optional KeePass key file.
- **Secret Settings**:
  - Path to the entry within the `.kdbx` file.
  - Which content to deploy: `password` or `attachment`.
  - Optional attachment name if the entry contains multiple attachments.
- **Validations**:
  - `.kdbx` file exists.
  - The file can be unlocked.
  - The requested entry exists.
  - The requested password field or attachment exists.
  - Deployments batch all requested KeePass entries for the backend so one database unlock can satisfy many secret reads.
  - The batch request payload is streamed to the helper on stdin.
  - The batch read returns a JSON response with base64-encoded secret bytes, and the deployment script materializes the staged files locally before encryption and transfer.

#### 3. **Vault** (Unimplemented)
Secrets are retrieved from a Vault instance.
If the secrets should always be accessed locally, the deployment user would copy them from Vault into the remote file location.
If services should access Vault directly, the remote machine would need the required Vault credentials.

- **Secret Store**: Vault server.
- **Global Settings**:
  - Deployment account name.
- **Secret Settings**:
  - Secret identifier in Vault.
  - Service account identifier for retrieval.
  - **Remote Only**:
    - Default: `true`
    - Secrets are accessed directly from the Vault API and not stored locally.
- **Validations**:
  - Vault is reachable.
  - Deployment user has access to secrets.
  - Service account credentials can be generated and deployed as needed.
