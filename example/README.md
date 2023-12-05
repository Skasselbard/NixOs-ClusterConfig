# Examples

These example should illustrate the usage of the project.

To run test examples on your own VMs or machines check the following:
- The device paths in the partitioning configuration.
  - You probably have to boot the machine into a Linux (e.g. one of the generated ISOs or a NixOs default installation ISO) find the correct drive in `/dev`.
- The `colmena.deployment.targetHost` if you use dynamic IPs.
  - You may have to boot the machine as for the device path.
- The interface used for Kubernetes.
  - TODO:
- Make sure an ssh key is in `~/.ssh/id_rsa.pub`, or configure a different one.
- If you base your configuration on the ones in here, mind the content of the `common` folder.

## Simple VM

A bare minimum configuration for an **EFI** VM.

This example shows the basic workflow.
For all following examples, the same steps have to be executed but may not be laid out as detailed as here.
If you want to define an own host, this configuration might be a good start.

- User: `admin`
- Password: `test`

### Stage-0

Generate the installation ISO:

```bash
./staged-hive install -n simpleVM
```

The ISO image will be created in `example/generated/simpleVM/iso/iso/nixos.iso`

### Stage-1

1. Use the image from `example/generated/simpleVM/iso/iso/nixos.iso` as CD drive image in your VM configuration.
2. Start the vm
3. Optional: connect to the vm via ssh using the host configured in `colmena.deployment.targetHost`
4. Run the `setup` script inside the vm
5. Type `y` to format the storage drive
6. Reboot from the storage drive after the installation finished

### Stage-2

Deploy the hive configuration:

```bash
./staged-hive hive deploy --on simpleVM
```

Since nothing irrelevant for the installation process was configured, this should not change the VM.

## ZFS VM with Dual Boot

This example shows the configuration with a more complex partitioning scheme.

The VM defines two disks, one for Linux and one for windows.
The boot device is the Linux disk.
It is best to have windows on a separate disk, because windows may break the Linux bootloader otherwise.

In this example, windows does not need the whole disk, making room for an additional linux partition at the end that can be added to the zpool.
However, disko cannot handle partial application ([it may be added in the future](https://github.com/nix-community/disko/issues/264)), which makes partitioning harder.

As a workaround we can define the space needed by windows without a file system in the `partitioning.format_disko` option.
This will still break the partition when the formatting script is applied, but the filesystem can be restored.
In this case, for a ntfs file system, the partition can be restored with `ntfsfix`.
A script doing that is added to the `setup.scripts` option and will be available in the installation ISO.
For `ext` file systems `fsck` can be used for restoration.

### Stages

The stages are mostly identical to the [simple VM](#simple-vm).
However, it might be useful to run the partitioning scripts from the installation ISO manually before the setup script:

```bash
sudo disko-format
fix_windows
setup
```

You can then skip the formatting in the setup script by typing `n`.
But make sure to format the zfs partition at least once while booted in the ISO.
If not, meaning you reboot in between formatting and setup, the bootloader seems to break for some reason and the system will not boot after setup.

If you setup your machine for the first time, you may want to format the windows partition as well.
This can be done with an additional script:

```bash
sudo disko-format-ALL
```