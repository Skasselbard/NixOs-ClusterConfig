# Secret Management for NixOS Deployments

## Overview

Secret management involves securely defining, distributing, and using sensitive data such as passwords, API keys, and certificates. This framework outlines a four-phase approach for handling secrets in NixOS deployments.

### Phases
1. **Secret Definition**: Configuration of secrets in the secret store and machine users.
2. **Machine Deployment**: Secure transfer of secrets to remote machines.
3. **User Deployment**: Distribution and setup of secrets for specific users or services.
4. **Secret Usage**: Secure access to secrets by services or users.

---

## Components

1. **Secret Store (Backend)**: The system where secrets are stored (e.g., files, Keepass, or Vault).
2. **Machine Deployment Mechanism (Script)**: Handles transferring secrets to remote machines.
3. **User Deployment (Systemd Service)**: Ensures secrets are accessible to the correct user accounts or services.
4. **Secret Access (Command or File)**: Enables usage of secrets, either through direct file access or decryption commands.

---

## Deployment Phases

### Phase 1: Secret Definition
- Secrets are manually created in the secret store by a **local user**.
- NixOS configuration defines users and associates them with secrets.

### Phase 2: Machine Deployment
- Secrets are transferred from the local machine to remote machines by a **deployment user**.
- Credentials for the secret store are requested at runtime.
- Secrets are validated, and deployment halts on errors.
- Secrets are stored in a central location on the remote machine to `/var/lib/nixos-secret-service/`.
- Secrets will be overwritten on redeployment.
- Access to the central location on the remote machine is restricted to the **secret service user**.

### Phase 3: User Deployment
- Secrets are distributed on the remote machine by the **secret service user** using a systemd service.
- Secrets are handled based on type:
  1. **Encrypted at Rest**:
     - Accessed via a auto generated decryption/retrieve command.
     - Required credentials are deployed with/instead of the secret.
  2. **Stored in Files**:
     - Stored with restrictive access permissions.
- Secrets are bind-mounted to `/dev/shm/nixos-secret-service/${user}/${secret}`.
- Additional, outdated bind mounts are removed.
- Ownership is assigned to the secret service user.
- Services can only access their own bind mounts.

### Phase 4: Secret Usage
- Secrets are accessed by a **service account** or **user account**, depending on type:
  1. **Encrypted at Rest**:
     - Accessed through the generated decryption/retrieve command.
     - Authentication is required during access.
  2. **Stored in Files**:
     - Directly accessed with appropriate file permissions.

---

## Supported Backends

### Common Settings
- **Backend Path**:
  - Used to Identify the secret.

#### Validations
- The remote is accessible.
- Target directories exist or can be created.

### Backend Types

#### 1. **Files**
Secrets are stored in local files on the machine.

- **Secret Store**: File location on disk.
- **Secret Settings**:
  - Local file path.
- **Validations**:
  - The file is accessible.

#### 2. **Keepass** (Unimplemented)
Secrets are stored in a `.kdbx` file.
Secrets are extracted during deployment and saved as files on the remote machine.

- **Secret Store**: `.kdbx` database.
- **Global Settings**: 
  - Path to the `.kdbx` file.
- **Secret Settings**: 
  - Path to the secret within the `.kdbx` file.
- **Validations**:
  - `.kdbx` file exists.
  - The file can be unlocked.

#### 3. **Vault** (Unimplemented)
Secrets are retrieved from a Vault instance.
If the secrets should always be accessed locally, the deployment user only copies the secret from vault to the remotes file location.
For access via vault api, vault credentials need to be deployed on the remote.

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
