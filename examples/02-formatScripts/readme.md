# Formatting Example

Use the ``deployment.formatScript`` option during an initial setup to prepare the machine storage drives.

## Prerequisites

- Three virtual machines you can deploy to.
  - You may have to change the NixOs configuration in [Configs Folder](../00-exampleConfigs/).
- Add the SSH private key from the [Config Folder](../00-exampleConfigs/secrets/sshKey) to your [SSH Agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent)

## Result

A different script executed for formatting during deployment:
- vm0 skips formatting and installs the new system over the old (from [example 01](../01-simpleCluster/))
- vm1 formats the vm device as configured in the ``disko`` attribute in the [NixOs Configuration](../00-exampleConfigs/machines/vm.nix).
- vm2 extracts the format script from the ``disko`` attribute manually and prints a dummy line before and after the extracted script (during machine creation)

## Deployment

1. Build the iso images with ``nix build .#vmX.iso``
   - you can also use the iso build in the last example
2. Start the three virtual machines, each one booting from a drive where one of the iso images is mounted
3. Deploy the complete machine configuration to the booted machines with ``nix run .#vmX.create``
   - you can run ``bash deploy.sh`` from this folder to deploy all three machines from the `build` sub-folder

## Test Setup

During deployment, vm0 should print a message instead of the formatting step and vm2 should print additional messages before and after formatting.

