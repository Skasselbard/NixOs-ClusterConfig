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
- Secrets are stored in a central location on the remote machine to `/run/nixos-secret-service/configuration`.
- Outdated secrets will be removed from the remote.
- Access to the central location on the remote machine is restricted to the **secret service user**.
- If needed, credentials to the secret store are stored as well

### Phase 3: User Deployment
- Secrets are distributed on the remote machine by the **secret service user** using a systemd service.
- Secrets are handled based on type:
  1. **Encrypted at Rest**:
     - Accessed via a auto generated decryption/retrieve command.
     - Required credentials are deployed with/instead of the secret.
  2. **Stored in Files**:
     - Stored with restrictive access permissions.
- Secrets are bind-mounted to `/run/nixos-secret-service/${account}/${secret}`.
- Additional, outdated bind mounts are removed.
- Ownership is assigned to the secret service user.
- Services access bind mounts with group permissions, ensuring isolation and security.

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
- **Remote File Path**:
  - Default: `/run/nixos-secret-service/${account}/${secret}`
  - Set to `null` if the secret is retrieved directly from a network store (e.g., Vault).
- **Encryption at Rest**:
  - Default: `true`
  - Requires decryption for usage.
  - Secrets cannot be accessed by just the file path.

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
  - File permissions restrict access to the owner and group.

#### 2. **Keepass**
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

#### 3. **Vault**
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







# Secret Service for NixOS Deployments

## Overview

This framework provides a structured approach for managing sensitive data (e.g., passwords, API keys, certificates) in NixOS deployments. It ensures secure definition, distribution, and usage of secrets while maintaining flexibility for various backends.

### Phases
1. **Secret Definition**: Configure secrets in a secret store and NixOS user settings.
2. **Machine Deployment**: Securely transfer secrets to remote machines.
3. **User Deployment**: Set up and distribute secrets for specific users or services on the remote.
4. **Secret Usage**: Enable secure access to secrets by services or users.

---

## Deployment Phases

### Phase 1: Secret Definition
- Secrets are defined in the secret store by a **local user**.
- NixOS configuration maps secrets to users or services:
  ```nix
  users.users = {
    alice = {
      secrets = {
        db-password = {
          backend = "vault";
          config = { path = "secret/db-password"; };
        };
        api-key = {
          backend = "file";
          config = { path = "/path/to/api-key.enc"; decryptCommand = "gpg --decrypt"; };
        };
      };
    };
  };
  ```

---

### Phase 2: Machine Deployment
- Secrets are securely transferred from the local machine to the remote.
- Validations ensure:
  - Backends are reachable.
  - Credentials are available at runtime.
  - Directories exist or are created.
- Outdated secrets are removed during deployment.
- Secrets are stored centrally on the remote machine at `/run/nixos-secret-service/configuration`.
- Only the **secret service user** has access to this central location.
- If backend credentials are required, they are securely stored for use in later phases.

---

### Phase 3: User Deployment
- Secrets are distributed locally by the **secret service user** via a systemd service.
- Distribution tasks include:
  1. **Encrypted Secrets**:
     - Decrypted on access using an auto-generated retrieve command.
     - Decryption credentials are stored securely.
  2. **Plain Secrets**:
     - Stored as files with restrictive permissions.
- Secrets are bind-mounted to `/run/nixos-secret-service/${account}/${secret}` for services to access.
- Additional security measures:
  - Outdated bind mounts are automatically removed.
  - Ownership is assigned to the secret service user.
  - Services access secrets with group permissions.

---

### Phase 4: Secret Usage
- Services or users access secrets based on their type:
  1. **Encrypted Secrets**:
     - Accessed through a retrieve/decrypt command:
       ```bash
       /run/nixos-secret-service/retrieve --account alice --secret db-password
       ```
     - Errors are logged to `stderr`.
  2. **Plain Secrets**:
     - Accessed directly from the bind-mounted file location.
- Access revocation occurs automatically when secrets are removed from the NixOS configuration.

---

## Supported Backends

### Common Settings
- **Remote File Path**:
  - Default: `/run/nixos-secret-service/${account}/${secret}`
  - Set to `null` for remote-only access (e.g., via Vault API).
- **Encryption at Rest**:
  - Default: `true`
  - Secrets require decryption before usage.

### Backend Types

#### 1. **Files**
Secrets stored as local files.

- **Store**: File location on disk.
- **Secret Settings**: Local file path.
- **Validations**:
  - File is accessible and has proper permissions.

#### 2. **Keepass**
Secrets stored in a `.kdbx` database.

- **Store**: `.kdbx` file.
- **Global Settings**: Database file path.
- **Secret Settings**: Path to secret within the database.
- **Validations**:
  - Database exists and can be unlocked.

#### 3. **Vault**
Secrets retrieved from a Vault instance.

- **Store**: Vault server.
- **Global Settings**: Deployment account name.
- **Secret Settings**:
  - Vault path for the secret.
  - Remote-only access (`true` by default).
- **Validations**:
  - Vault is reachable.
  - Deployment user has appropriate access.

---

## Additional Notes

1. **Vault Access Configuration**: Not included. Users must configure Vault access policies.
2. **Audit Logging**: Recommended as a backend feature (e.g., Vault audit logs).
3. **Access Revocation**: Secrets are automatically removed from deployed files and bind mounts if they are no longer defined in the NixOS configuration.
4. **Fail-Safe Mechanism**: Services should handle missing or inaccessible secrets gracefully. Decryption errors are logged for debugging.

---

## Example Flow

1. Define secrets in `users.users` and backend configurations in NixOS.
2. Run the machine deployment script to transfer secrets to remotes.
3. Systemd services on the remote distribute and bind-mount secrets for user-specific access.
4. Services securely access secrets at their designated paths.
