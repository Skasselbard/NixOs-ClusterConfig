# Simple Cluster Example

## Objective

Use HomeManager modules on a per (cluster)user basis to customize the user experience.

## Prerequisites

- Three virtual machines you can deploy to.
- Reuse the deployed machines from the [Simple Cluster Example](../01-simpleCluster/)
  - Or build the ISOs and deploy the system again as described in the Simple Cluster Example
- Add the SSH private key from the [Config Folder](../00-exampleConfigs/secrets/sshKey) to your [SSH Agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent)

## Result

Three VMs with two cluster users (that are deployed on all machines in the cluster).
The ``root`` user does not import custom HomeManager configuration,
while the ``admin`` user deploys a starship configuration for bash.
If you connect with the admin user the bash prompt should be colored
(you may need nerdfonts on your working machine to display all symbols correctly).
If you connect with root, the default prompt should be used.

## Deployment

If you haven't, deploy a base system as described in the [first example](../01-simpleCluster/).
Then run

```bash
nix run .#colmena apply
```

You can also run the deployment script with ``bash deploy.sh``.

## Test Setup

