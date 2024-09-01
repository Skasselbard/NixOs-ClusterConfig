# Deploy the Examples

## 0. Prerequisites

- A set of configurable and runnable VMs (count depends on the example)
  - the os storage drive will be expected under `/dev/disk/by-id/virtio-OS`
- add the ssh keys from the example to your ssh-agent (create your own keys for your production cluster)
  ```bash 
  ssh-add examples/00-exampleConfigs/secrets/sshKey
  ```

## 1. cd to example folder

```bash
  cd examples/01-simpleCluster
```

## 2. Build iso files for initial vm setup

```bash
  nix build .#machineName.iso
```

## 3. Configure VM

- load iso as cd-rom
- set the boot order to boot from cd-rom