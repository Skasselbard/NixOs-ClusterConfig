
| :warning: **Depricated**   
|:------------------------|
|The steps described in this documentation are deprecated und need to be reworked|

<!-- TODO: rework usage steps -->

# Generated Flake attributes

- `nixosConfigurations.<hostname>`: nixos configurations for all defined hosts
- `packeges.<system>.<hostname>`.
  - `create`: build by nixos-anywhere module, script to remotely deploy this host to `deployment.targetHost`
  - `format`: TODO:
  - `hardware-configuration`: TODO:
  - `iso`: build an image for the host with nixos-generators with `nix build .#<hostname.iso>`
- `apps.colmena`: make colmena executable with TODO: command
- `colmena`: a colmena hive definition for deployment with colmena

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


| :warning: **Depricated**   
|:------------------------|
|The steps described in this documentation are deprecated und need to be reworked|

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


| :warning: **Depricated**   
|:------------------------|
|The steps described in this documentation are deprecated und need to be reworked|


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


| :warning: **Depricated**   
|:------------------------|
|The steps described in this documentation are deprecated und need to be reworked|

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


| :warning: **Depricated**   
|:------------------------|
|The steps described in this documentation are deprecated und need to be reworked|

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


| :warning: **Depricated**   
|:------------------------|
|The steps described in this documentation are deprecated und need to be reworked|

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