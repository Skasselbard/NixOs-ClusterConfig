

# Secret-Service Cluster Module
## **Overview**
`clusterModule.nix` defines a **deployment mechanism** for secrets across a cluster of machines. It:
- **Generates a deployment script** (`deploy-secrets.sh`) that:
  - Retrieves secrets from backends.
  - Encrypts them using `gocryptfs`.
  - Transfers the encrypted archive to the remote machine.
- **Provides a connection script** (`connect-secrets.sh`) to automate SSH-based deployment.

---

## **How It Works**
These steps are done for deployment:

1. **Read Secrets Configuration**  
   - Iterates over `users.users.<user>.secrets.<backend>.<secret>` to retrieve each user's secrets.

2. **Secrets Validation**  
   - Execute one backend-level validation command per used backend.
   - **Aborts deployment** if any secret is missing or unreadable.

3. **Encrypt Secrets**  
   - Generates an **encryption key** from deployment metadata.
   - Initializes a **gocryptfs-encrypted** directory.
   - Stores secrets inside the encrypted folder as files.

4. **Transfers Encrypted Secrets to Remote Machine**  
   - Copies encrypted archive (`secrets.enc`) via **rsync**.
   - Stores metadata (`deployment-info.json`) remotely.

5. **Connection Script (`connect-secrets.sh`)**  
   - **Tries multiple SSH users** (`secret-service`, deployment user, root).
   - If a connection succeeds, runs the deployment script.

---

## **Configuration Options**
### **1. Deployment Options**

- `services.secrets.deployment.tempPath` defaults to `/dev/shm/nixos-secret-service` and stores secrets in RAM before encryption.
- `services.secrets.deployment.persistentPath` defaults to `/var/lib/nixos-secret-service` and stores the encrypted payload on the remote machine.
- `services.secrets.deployment.database.fileName` defaults to `secrets.enc`.
- `services.secrets.deployment.metadata.fileName` defaults to `deployment-info.json`.

<!-- ### **2. Backend Configuration**
| Option | Description |
|--------|-------------|
| `services.secrets.backends.<backend>.retrieveSecretCommand` | Retrieves a secret. |
| `services.secrets.backends.<backend>.validateSecretCommand` | Validates a secret’s existence & permissions. | -->

### **2. Backend Highlights**
- `file`: Reads a local file directly.
  - `backendPath` is the file system path in the form to the secret on the deployment machine.
- `keepass`: Reads a local KeePass `.kdbx` database through the Rust helper CLI in `keepass-cli/`.
  - `backendPath` is the KeePass entry path in the form `group/subgroup/entry`.
  - `content = "attachment"` deploys one attachment from the entry.
  - `content = "password"` deploys the KeePass password field.
  - `attachmentName` is optional and only needed when an entry has multiple attachments.
  - `services.secrets.backends.keepass.passwordCommand` can populate `SECRET_SERVICE_KEEPASS_PASSWORD` for non-interactive deployments.

Deployment treats every backend as a batch: each used backend is prepared once, validated once, and retrieved once for the full set of configured secrets assigned to it.

KeePass deployments stream one batch request payload to the helper over stdin for validation and reading. The batched read returns a JSON response with binary-safe base64 payloads, and the deployment script writes the staged files itself before `gocryptfs` encryption, so the overall secret-service flow still operates on files in the temporary deployment directory.

### **3. KeePass Example**

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

## **Deployment Workflow**
1. **Run the deployment script manually or from CI/CD:**
   Add the Module to your cluster config. TODO: example
2. Run `nix run .#machines.<machine-name>.deploySecrets`

---



# Secret-Service Nixos-Module

## **Machine Module Overview**

The **Secret Service** Nixos-Module on a remote machine, responsible for:
- **Decrypting the received archive** (`secrets.enc`).
- **Mounting secrets dynamically** using `gocryptfs`.
- **Providing access to secrets per user**.

---

## **Machine Module Flow**

The logic is done in a systemd service.
1. **Mounts the Encrypted Secret Archive**
   - Retrieves the **encryption key** from metadata.
   - Uses `gocryptfs` to **decrypt the archive in RAM** (`/dev/shm/nixos-secret-service`).

2. **Creates Bind Mounts Per User**
   - Extracts **users with secrets** from `users.users.<user>.secrets`.
   - Creates **bind mounts** at `/run/nixos-secret-service/<user>`.
   - Sets **read only permissions** for each users secret.

3. **Handles Secure Unmounting**
   - Secrets are **unmounted on service stop**.

---

## **Machine Module Configuration**
### **1. Deployment Paths**

- `services.secrets.deployment.persistentPath` defaults to `/var/lib/nixos-secret-service` and stores the encrypted archive.
- `services.secrets.deployment.tempPath` defaults to `/dev/shm/nixos-secret-service` and stores the decrypted mount in RAM.

<!-- ### **2. Encryption Configuration**
| Option | Default | Description |
|--------|---------|-------------|
| `services.secrets.deriveEncryptionKey` | `jq .configHash | sha256sum | awk '{print $1}'` | Generates encryption key. | -->

---

## **Example Workflow**
1. **Deploy secrets using `connect-secrets.sh`.**
2. **On the remote machine:**
   - **The systemd service decrypts and mounts secrets.**
   - **Users can access their bind-mounted secrets securely.**
3. **Stopping the service unmounts all secrets.**
