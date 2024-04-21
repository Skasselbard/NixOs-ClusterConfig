# Nixos Staged Hive

Build and deploy a set of [NixOs](https://nixos.org/) machines for Kubernetes in a home cloud.

This project tries to automate the installation process of multiple NixOs machines as far as possible for home use.
The goal is to take virgin machines and boot up a configuration that can be managed with colmena.
A secondary goal is to configure [K3s](https://k3s.io/) on a subset of these machines.

During the switch to nix flakes, this project got quite a bit simpler.
As a result, what now is stage two is more of a hint or a guide line and not reflected in the tools anymore.

## Goals

1. Create installation media for an initial machine setup
2. Deploy updates and change configuration remotely once the machines are initialized
3. Keep the human interaction minimal in the process
4. Do as much configuration declarative as possible
5. Provide a minimal configuration for a K3s cluster on NixOS


# Additional Features

- partitioning module with disko
- (WIP) generating ``hosts`` file entries for static hosts
- (WIP) k3s kubernetes module (containerized)
  - initialized with k3s manifest files
  - Maybe: with configurable argocd (but probably only in an example manifest)
- fixable versions with flakes
- Maybe coming: print a configuration summary (e.g. for the ip configuration)

# Assumptions

There are some assumptions that are embedded in the project.
Some keep the configuration minimal and structured.
Others reflect personal taste.

The following assumptions may be of interest:

- You running a linux system (with nix installed) for deployment.
- flakes are used is a central source of configuration
- Hosts are accessible by ssh
- The data on the installation medium is disposable and can be overwritten

# Stages

The installation process is devised into stages:

0. Installation medium with network config
1. [nixos-anywhere](https://github.com/nix-community/nixos-anywhere/tree/main) remote installation
2. Nixos configuration management
3. Optional: K3s Kubernetes configuration

## Stage 0: Bootable Iso Image for Installation Medium

- build a bootable image for the initial machine setup
  - used to for remote system install (stage 1)
- physical access to the machine is needed but should be kept to a minimum
  - the internet has to be reachable
- can be used to retrieve the hardware-configuration.nix hardware-configuration.nix



## Stage 1: Remote Installation with [nixos-anywhere](https://github.com/nix-community/nixos-anywhere/tree/main)
- an initial intermediate installation
  - installed from the image from stage 0
  - extended to the full system with colmena in stage 2
- optional: partitioning with [disko](https://github.com/nix-community/disko/tree/master)
  - the partitioning module helps to define formatting scripts
  - since disko currently [cannot handle partial application](https://github.com/nix-community/disko/issues/264#issuecomment-1591625257) you can split the disk configuration in ephemeral and persistent storage. If you deploy by using `lib.deploy`, only the ephemeral config will be wiped by default.


## Stage 2: Nixos Configuration Management
- To manage your host you can run `nixos-rebuild` for remote hosts by specifying a `target host`.
Example:
```bash
nixos-rebuild --flake .#<nixosConfiguration> switch --target-host "root@<ip>"
```
- You can also use deployment tools like [Colmena](https://github.com/zhaofengli/colmena) or [NixOps](https://github.com/NixOS/nixops)


# Usage

## Include the project and other tools in your flake

Example:
```nix
{
   inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    hive = {
      url = "github:/Skasselbard/NixOs-Staged-Hive";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko"; # Use your preferred disko version
    };
    # You can lock your preferred disko version
    disko = {
      url = "github:nix-community/disko/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Nixos generators is used to build the installation images
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ...
 };
 # ...
}
```

## Configure your machines

1. Include all dependencies.
2. Define your disko devices
  - I find it useful to make a separate definition for each physical device
  - You can use the `mergeDiskoDevices` function provided by this projects `lib` to merge them together.
3. Include your disko devices with the `partitioning` module of this project
  - ephemeral devices will get wiped in the remote installation (stage 1).
    - For NixOs it is useful to include the OS device in the ephemeral storage.
  - persistent devices will not be formatted by default
    - Use this for all devices that should not be touched in a possible future reinstallation of the system or already formatted data drives

| :warning: **Notice**   
|:------------------------|
| Only add entire devices to a partitioning type (ephemeral or persistent). Do not split disko configuration for a single device (e.g. drive or zpool). However, different devices can be put in different partitioning types. If you format a device partially the partition table will differ from the combined disko configuration (ephemeral + persistent). Your configuration will not work without intervention in this case.



Example:

```nix
{
  outputs = inputs@{ self, nixpkgs, hive, disko, nixos-generators, ... }:
    with hive.lib;
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      nixosModules = {
        machines = with self.nixosModules.storage; {
          test = with builtins; {
            inherit system;
            modules = [ 
              # hive include for partitioning (WIP: and kubernetes)
              hive.nixosModules.default
              # disko include to build custom formatting scripts in the hive module
              disko.nixosModules.default
              {
              partitioning = {
                # Usually the os can be wiped if the machine should be reinstalled
                # so the os device can be ephemeral
                ephemeral = (mergeDiskoDevices [ devices.test-os ]);
                persistent = (mergeDiskoDevices [ 
                  devices.test-persistent1
                  devices.test-persistent2 
                ]);
              };
            }];
          };
        };
        storage = {
          devices = {
            test-os = { disk = {
              # your disko config
            };};
            test-persistent1 ={ disk = {
              # your disko config
            };};
            test-persistent2 ={ disk = {
              # your disko config
            };};
          };
        };
      };
      # define your host configuration
      nixosConfigurations = {
        test = nixpkgs.lib.nixosSystem self.nixosModules.machines.test;
      };

      # ...

    };
}
```

Test your configuration:
```shell
nixos-rebuild --flake .#test build
```

## Prepare an installation medium

You can use `nixos-generators` and this projects lib to crate installation isos for the remote
installation system.

Example:

```nix
{
  outputs = inputs@{ self, nixpkgs, hive, disko, nixos-generators, ... }:
    with hive.lib;
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {

      # ...

    packages.${system} = with hive.lib; 
      with self.nixosConfigurations;{
       # use nixos-generators to build an installation iso
       iso = nixos-generators.nixosGenerate ({
           format = "iso";
         # You can find a configurable nixos image in a helper function of this project
         } // hive.outputs.nixosModules.bootImage {
           ip = "192.168.122.100"; # The ip address of the booted installer system
           rootSSHKeys = # A list of ssh keys to reach the system (as root)
             [ (builtins.readFile "${self}/userConfigs/sshKeys/default") ];
         });
       };
    };
}
```

Build the system:

```shell
nix build .#iso 
```

`nix build` will link the result in $PWD.
You can than use `dd` or another tool to copy the iso to an installation medium
(or use the iso directly in a vm).


## Deploy your complete configuration

You can use `lib.deploy` from this project to run `nixos-anywhere` with your settings.
The `deploy` function will reset the formatting script used by nixos-anywhere
to only format the config under `partitioning.ephemeral`.
If you want to wipe the entire configuration set `wipePersistentStorage = true;` in the
function call.

Example:

```nix
{
  outputs = inputs@{ self, nixpkgs, hive, disko, nixos-generators, ... }:
    with hive.lib;
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {

      # ...

    packages.${system} = with hive.lib; 
    with self.nixosConfigurations;{
      # Use the deploy function to run nixos-anywhere
      deployTest = deploy {
         config = test.config;
         ip = "192.168.122.100"; # use the ip configured in the iso
         extraArgs = [ "--tty" ]; # provide [extraArgs](https://github.com/nix-community/nixos-anywhere/blob/main/src/nixos-anywhere.sh)
         # wipePersistentStorage = true; # If uncommented: wipe all configured devices
      };
    };
  };
}
```

- Boot your machine from the installation medium.
- run nixos-anywhere:

```shell
nix run .#deployTest  
```

# Build and run custom formatting scripts

If you need to reformat a set of your devices you can build and run a custom format script
with the `lib.formatScript` function of this project.

Example:

```nix
{
  outputs = inputs@{ self, nixpkgs, hive, disko, nixos-generators, ... }:
    with hive.lib;
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {

      # ...

    packages.${system} = with hive.lib; 
    with self.nixosConfigurations;{
      format = hive.lib.formatScript { ip = "192.168.122.100"; }
            # e.g. the second persistent storage changed and needs to be formatted
            [ self.nixosModules.storage.devices.test-persistent2 ];
    };
  };
}
```

Run the script:

```shell
nix run .#format
```