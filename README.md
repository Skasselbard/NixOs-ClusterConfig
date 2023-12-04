# Nixos Staged Hive

Build and deploy a set of [NixOs](https://nixos.org/) machines for Kubernetes in a home cloud.

This project tries to automate the installation process of multiple NixOs machines as far as possible for home use.
The goal is to take virgin machines and boot up a configuration that can be managed with colmena.
A secondary goal is to configure [K3s](https://k3s.io/) on a subset of these machines.

## Goals

1. Create installation media for an initial machine setup
2. Deploy updates and change configuration remotely once the machines are initialized
3. Keep the human interaction minimal in the process
4. Do as much configuration declarative as possible
5. Provide a minimal configuration for a K3s cluster on NixOS


# Additional Features

- partitioning module with disko
- generating ``hosts`` file entries for static hosts
- In Progress: k3s kubernetes module (containerized)
  - initialized with k3s manifest files
  - Maybe: with configurable argocd (but probably only in an example manifest)
- fixable versions
- extendable setup phase (with scripts and files)
- Maybe coming: print a configuration summary (e.g. for the ip configuration)

# Assumptions

There are some assumptions that are embedded in the project.
Some keep the configuration minimal and structured.
Others reflect personal taste.

The following assumptions may be of interest:

- You running a linux system (with nix installed) for deployment.
- every nix file or folder in the given path is a machine definition
- The nix configuration is built on the deploying machine
- Each host has an admin user
- Hosts are accessible by ssh
  - ssh connections prohibit passwords and root logins (only ssh keys are allowed)
  - the admin user has a password for sudo once an ssh connection is established
- The data on the installation medium is disposable and can be overwritten

# Stages

The installation process is devised into stages:

0. Installation medium with network config
1. Minimal System with network config
2. [Colmena TODO: link]() Hive
3. Optional: K3s Kubernetes configuration

## Stage 0: Bootable iso image for installation medium

- build a bootable image for the initial machine setup
  - used to install the minimal system (stage 2)
  - started by the `setup` script available in `$PATH`
- physical access to the machine is needed but should be kept to a minimum
- the installation prozess should be possible remotely
  => network and user configuration is necessary
  - the internet has to be reachable
- optional: partitioning schould be done decleratively
  => uso of [disko TODO: link]()
  => disko configuration is needed on the bootable image
- setup process should extendable (see `setup` options)
  - scripts and files can be added to the image
  - scripts can be added to the execution of the `setup` script before and after the nixos installation

## Stage 1: minimal system configuration for Colmena setup
- an initial intermediate installation
  - installed from the image from stage 0
  - extended to the full system with colmena in stage 2
- should be as small as possible for quick installation
  - boot options have to be set according to the machine constraints
  - optional: partitioning should be setup as configured
  - networking and user configuration has to be set up
- hardware-configuration.nix should be retrieved
- resulting host has to be reachable for the hive configuration in stage 3
- the configuration has to be independent from additional nix modules (and other local files) so that it can be installed from the iso environment
  - resolving all dependencies, if possible at all, is not worth the effort

## Stage 2: Colmena Hive Deployment
- All hosts are composed into a Colmena hive definition file and deployed.
- A hive declaration should be generated
  - should be generated from normal nixos declarations (configuratin.nix)
  - information from the nixos configuration should be reused when possible
  - nixos version should be configurable

# Mechanism

The `nixos-staged-hive` script wraps all functionality.
It calls a python script in a nix-shell environment.
All functionality is composited in the `hive.py` python script and excessable via subcommands.
On execution these things are done:

1. A folder named `nixConfigs` with nixos definitions (nix files) is read
   - every top level folder and file in `nixConfigs` is assumed to be a machine definition
2. crawl each definition and parse specific nixos options defined by modules from this project (mainly user, ssh and network options)
3. generate a nix file for each stage with the parsed options
   - the generated folder is named after the foldername (or file name) parsed from `nixConfigs`
   - an `iso.nix` is generated for each host to build the stage 0 image
   - a `mini_sys.nix` is generated for each host to build the mini system declaration used in stage 1
   - a `hive.nix` is generated for all host to be used by colmena in stage 2
4. depending on the sub command following functionality can be accessed
   1. TODO: setup: create the necessary folder structure
   2. install:
     - generate the iso for a single host and optionally write it on a boot medium
   3. hive:
     - Wrapper around colmena with the previous generation steps included

# Usage FIXME: Test the commands
## Download the scripts and set up the configuration

```shell
curl -sSf https://raw.githubusercontent.com/Skasselbard/NixOS-Staged-Hive/main/install.sh | sh
```

## Prepare an installation medium

```shell
./nixos-staged-hive install -n testvm -d /dev/USBdevice
```

## Boot from the installation medium and run the setup a base system with your user and IP congifuration

On the machine:
```shell
setup
```

## Deploy your complete configuration

```shell
./nixos-staged-hive hive deploy [colmena-args]
```

for disko partitioning
- get device ids from iso boot
- generate hostID for zfs hosts
- write disko config
- fix partially formatted disk
  - run fsck for ext file systems
  - run ntfsfix for ntfs file system
  - best practise:
    - manually format with ``sudo disko-format`` before running the setup script


## TODO: Fixable Versions

- NixOs Versions:
- Disko Versions:
- k3s versions: take a tag from here https://hub.docker.com/r/rancher/k3s/tags #FIXME: Version is not used for server container

# Known Issues

- partially formatted EFI host does not boot into the mini system after installation
  - this apparently happens for when I am testing around with formatting and skip the formatting step for an installation after a reboot
  - reformatting (partially) and reinstalling the mini system without a reboot avoids this issue for me