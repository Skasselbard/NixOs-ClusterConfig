# Simple Cluster Example

## Objective

Build a short functional cluster with three machines and a simple service.

## Prerequisites

- Three virtual machines you can deploy to.
  - You may have to change the NixOs configuration in [Configs Folder](../00-exampleConfigs/).
- Add the SSH private key from the [Config Folder](../00-exampleConfigs/secrets/sshKey) to your [SSH Agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent)

## Result

Three Virtual machines with:
- a fresh NixOs on previously formatted OS-Drive
- static ips as set in the [configuration](../00-exampleConfigs/default.nix)
- a root user with `root` as password
  - and an authorization to connect with the ssh key from the [Config Folder](../00-exampleConfigs/secrets)
- a hosts file with entries for all three machines in the cluster

## Deployment

1. Build the iso images with ``nix build .#vmX.iso``
   - replace the X with the number from the vm name in the cluster-config
   - you can run ``bash build-isossh.sh`` from this folder to build all three machines in a `build` sub-folder
2. Start three virtual machines, each one booting from a drive where one of the iso images is mounted
   - all machines are configured with a different ip as seen in the ``machine`` attribute in the [configuration file](../00-exampleConfigs/default.nix)
3. Deploy the complete machine configuration to the booted machines with ``nix run .#vmX.create``
   - replace the X with the number from the vm name in the cluster-config
   - you can run ``bash deploy.sh`` from this folder to deploy all three machines from the `build` sub-folder
4. Boot the virtual machines from the OS drive

## Test Setup

1. connect to a virtual machine with ssh: ``ssh 192.168.100.10``
2. from the vm test the connection to another machine: ``ping vm1``

You can also run the test script from this folder to test the configuration: ``bash test.sh``