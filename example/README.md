# Examples

To run test examples on your own VMs or machines check the following:
- The device paths in the partitioning configuration
  - you probably have to boot the machine into a Linux (e.g. one of the generated ISOs or a NixOs default installation ISO) find the correct drive in /dev
- The `colmena.deployment.targetHost` if you use dynamic IPs
  - You may have to boot the machine as for the device path
- The interface used for Kubernetes
  - TODO:
- Make sure an ssh key is in `~/.ssh/id_rsa.pub`, or configure a different one

## Simple VM

A bare minimum configuration for an **EFI** VM.

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