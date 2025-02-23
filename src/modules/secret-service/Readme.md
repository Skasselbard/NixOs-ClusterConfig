

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
   - Execute a backend dependent.
   - **Aborts deployment** if any secret is missing or unreadable.

3. **Encrypts Secrets**  
   - Generates an **encryption key** from deployment metadata.
   - Initializes a **gocryptfs-encrypted** directory.
   - Stores secrets inside the encrypted folder.

4. **Transfers Encrypted Secrets to Remote Machine**  
   - Copies encrypted archive (`secrets.enc`) via **rsync**.
   - Stores metadata (`deployment-info.json`) remotely.

5. **Connection Script (`connect-secrets.sh`)**  
   - **Tries multiple SSH users** (`secret-service`, deployment user, root).
   - If a connection succeeds, runs the deployment script.

---

## **Configuration Options**
### **1. Deployment Options**
| Option | Default | Description |
|--------|---------|-------------|
| `services.secrets.deployment.tempPath` | `/dev/shm/nixos-secret-service` | Temporary RAM location for secrets before encryption. |
| `services.secrets.deployment.persistentPath` | `/var/lib/nixos-secret-service` | Where encrypted secrets are stored deployed to. |
| `services.secrets.deployment.database.fileName` | `secrets.enc` | The encrypted archive filename. |
| `services.secrets.deployment.metadata.fileName` | `deployment-info.json` | Metadata file storing deployment info.|

<!-- ### **2. Backend Configuration**
| Option | Description |
|--------|-------------|
| `services.secrets.backends.<backend>.retrieveSecretCommand` | Retrieves a secret. |
| `services.secrets.backends.<backend>.validateSecretCommand` | Validates a secret’s existence & permissions. | -->

---

## **Deployment Workflow**
1. **Run the deployment script manually or from CI/CD:**
   Add the Module to your cluster config. TODO: example
2. Run `nix run .#machines.<machine-name>.deploySecrets`

---



# Secret-Service Nixos-Module

## **Overview**

The **Secret Service** Nixos-Module on a remote machine, responsible for:
- **Decrypting the received archive** (`secrets.enc`).
- **Mounting secrets dynamically** using `gocryptfs`.
- **Providing access to secrets per user**.

---

## **How It Works**

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

## **Configuration Options**
### **1. Deployment Paths**
| Option | Default | Description |
|--------|---------|-------------|
| `services.secrets.deployment.persistentPath` | `/var/lib/nixos-secret-service` | Stores encrypted archive. |
| `services.secrets.deployment.tempPath` | `/dev/shm/nixos-secret-service` | RAM-based decrypted storage. |

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
