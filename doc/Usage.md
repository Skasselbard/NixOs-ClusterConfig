
# Usage

- Follow the [examples](../examples/readme.md) for configuration guidances

# Generated Command Usage

## Build Artifacts
These commands are executed with ``nix build``.

### Machine Commands
``nix build .#machines.<machine name>.<command>``
**Commands**:
- **``iso``**: build an iso file for the machine

## Run commands
These commands are executed with ``nix run``.

### Machine Commands
``nix run .#machines.<machine name>.<command>``
**Commands**:
- **``build``**: run a nix build of the machine with nixos-rebuild
- **``deploy``**: deploy the machine to the deployment.target with nixos-rebuild
- **``connect``**: connect to the deployment.target via ssh
- **``hardware-configuration``**: connect to the deployment.target and print the hardware configuration.nix via ssh

### Machine Specific Service Commands
``nix run .#machines.<machine name>.services.<service name>.<command>``
These service commands assume that a systemd unit named "<service name>.unit" exists, which may not always be true (depending on the service implementation and configuration).
**Commands**:
- **``start``**: 1
- **``restart``**: deploy the machine to the deployment.target
- **``stop``**: connect to the deployment.target via ssh
- **``status``**: connect to the deployment.target and print the hardware configuration.nix via ssh
- **``log`**: connect to the deployment.target and print the hardware configuration.nix via ssh

## Module Commands
Commands that are exposed by a module.

### Nixos Anywhere
The Nixos Anywhere module adds machine commands.
``nix run .#machines.<machine name>.<command>``
**Commands**:
- **``create``**: Redeploys the entire nixos system on the deployment.target
- **``format``**: Runs the configured format script on deployment.target


# Stages

The installation process is devised into stages:

0. Installation medium with network config
1. [nixos-anywhere](https://github.com/nix-community/nixos-anywhere/tree/main) remote installation
2. Nixos configuration management

## Stage 0: Bootable Iso Image for Installation Medium

- build a bootable image for the initial machine setup with ``nix build .#machines.<machine name>.iso``:
  - used to for remote system install (stage 1)
- physical access to the machine is needed but should be kept to a minimum
  - the internet has to be reachable
- can be used to retrieve the hardware-configuration.nix hardware-configuration.nix

## Stage 1: Remote Installation with [nixos-anywhere](https://github.com/nix-community/nixos-anywhere/tree/main)
- run the initial image on from Stage 0 on the machine you want to set up
- run an initial installation with ``nix run .#machines.<machine name>.create``
- optional: partitioning with [disko](https://github.com/nix-community/disko/tree/master)
  - the partitioning module helps to define formatting scripts
  - the format script will be run as part of the nixos anywhere installation

## Stage 2: Nixos Configuration Management
- To update your machines you can run ``nix run .#machines.<machine name>.deploy``