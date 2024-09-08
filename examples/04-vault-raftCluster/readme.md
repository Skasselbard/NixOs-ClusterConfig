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
1. create certificates
2. Run
  ```bash
  nix run .#colmena apply
  ```
  - You can also run the deployment script with ``bash deploy.sh``.


## Test Setup
