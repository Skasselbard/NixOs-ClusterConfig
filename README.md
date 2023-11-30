# Assumptions

- every nix file or folder in the given path is a machine definition

# Stages

0. Installation medium with network config
1. Minimal System with network config
2. Colmena Hive

# Mechanism

1. get a folder with nixos definitions (nix files)
2. crawl each definition and parse specific nixos options defined by modules from this project (mainly user, ssh and network options)
3. generate a nix file for each stage with the parsed options

# Workflow

For each machine that does not run nixos already:

1. prepare boot medium
2. boot iso from boot medium
3. ?get hardware-configuration for the first time?
4. install mini system from an automatically generated setup script

For all machines

1. run colmena

for disko partitioning
- get device ids from iso boot
- generate hostID for zfs hosts
- write disko config
- fix partially formatted disk
  - run fsck for ext file systems
  - run ntfsfix for ntfs file system
  - best practise:
    - manually format with ``sudo disko-format`` before running the setup script

# Additional Features

- partitioning module with disko
- generating ``hosts`` file entries for static hosts
- In Progress: k3s kubernetes module (containerized)
  - initialized with k3s manifest files
  - Maybe: with configurable argocd (but probably only in an example manifest)
- fixable versions
- extendable setup phase (with scripts and files)
- Maybe coming: print a configuration summary (e.g. for the ip configuration)

# Known Issues

- partially formatted EFI host does not boot into the mini system after installation
  - this apparently happens for when I am testing around with formatting and skip the formatting step for an installation after a reboot
  - reformatting (partially) and reinstalling the mini system without a reboot avoids this issue for me
