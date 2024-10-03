# Vault Service Example

Use the Vault Cluster-Service to deploy a highly available Vault-Cluster on three Machines.

## Prerequisites

- Three virtual machines you can deploy to.
- Reuse the deployed machines from the [Simple Cluster Example](../01-simpleCluster/)
  - Or build the ISOs and deploy the system again as described in the Simple Cluster Example
- Add the SSH private key from the [Config Folder](../00-exampleConfigs/secrets/sshKey) to your [SSH Agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent)

## Result

- vault cluster
  - with distributed database (raft storage)
  - self signed certificate authority
  - intermediate certificates for tls communication
- ? account with github "sign in"
- vault agent as secret client
- ? (multiple) service with vault identity
  - ? maybe distributed ssh key(access)
  - ? maybe shared access to a resource

## Deployment

If you haven't, deploy a base system as described in the [first example](../01-simpleCluster/).
1. create certificates with
   - ``sudo nix run .#cluster.example.vault.createTlsCertificate``
   - ``sudo nix run .#example.vault.createRootCertificate``
2. Run the deployment script with ``bash deploy.sh``.
3. open the browser on one of the vault servers, e.g. :``https://192.168.122.200:8200``
   - ignore the security warning, your browser does not know about the certificates we created in step 1
4. create a new raft cluster
   - save the unseal key and root token
5. unseal the remaining vault servers
   - e.g. in the browser while connecting to the other servers like in step 3


## Test Setup
