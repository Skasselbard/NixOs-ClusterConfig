## admin\.hashedPwd

A password hash that should be used for the admin user\.
Can be generated e\.g\. wit ` mkpasswd -m sha-512 `\.



*Type:*
null or string



*Default:*
` null `

*Declared by:*
 - [NixOs-Staged-Hive/modules/admin\.nix](../modules/admin.nix)



## admin\.name



Name of the admin user of the system\.

A user with this name will be created and added to the ` wheel ` group\.
The password of the user will be assigned to the value of ` admin.hashedPassword ` and
the ssh keys configured in ` admin.sshKeys ` will be configured for remote access\.



*Type:*
string



*Default:*
` "admin" `

*Declared by:*
 - [NixOs-Staged-Hive/modules/admin\.nix](../modules/admin.nix)



## admin\.sshKeys



A list of ssh public keys that are used for remote access\.

Both the root user and the user configured with ` admin.name ` will be configured with this list\.



*Type:*
list of string

*Declared by:*
 - [NixOs-Staged-Hive/modules/admin\.nix](../modules/admin.nix)



## colmena\.deployment\.allowLocalDeployment



Allow the configuration to be applied locally on the host running
Colmena\.

For local deployment to work, all of the following must be true:

 - The node must be running NixOS\.
 - The node must have deployment\.allowLocalDeployment set to true\.
 - The node’s networking\.hostName must match the hostname\.

To apply the configurations locally, run ` colmena apply-local `\.
You can also set deployment\.targetHost to null if the nost is not
accessible over SSH (only local deployment will be possible)\.



*Type:*
boolean



*Default:*
` false `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.buildOnTarget



Whether to build the system profiles on the target node itself\.

When enabled, Colmena will copy the derivation to the target
node and initiate the build there\. This avoids copying back the
build results involved with the native distributed build
feature\. Furthermore, the ` build ` goal will be equivalent to
the ` push ` goal\. Since builds happen on the target node, the
results are automatically “pushed” and won’t exist in the local
Nix store\.

You can temporarily override per-node settings by passing
` --build-on-target ` (enable for all nodes) or
` --no-build-on-target ` (disable for all nodes) on the command
line\.



*Type:*
boolean



*Default:*
` false `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.keys



A set of secrets to be deployed to the node\.

Secrets are transferred to the node out-of-band and
never ends up in the Nix store\.



*Type:*
attribute set of (submodule)



*Default:*
` { } `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.keys\.\<name>\.destDir



Destination directory on the host\.



*Type:*
path



*Default:*
` "/run/keys" `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.keys\.\<name>\.group



The group that will own the file\.



*Type:*
string



*Default:*
` "root" `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.keys\.\<name>\.keyCommand



Command to run to generate the key\.
One of ` text `, ` keyCommand ` and ` keyFile ` must be set\.



*Type:*
null or (list of string)



*Default:*
` null `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.keys\.\<name>\.keyFile



Path of the local file to read the key from\.
One of ` text `, ` keyCommand ` and ` keyFile ` must be set\.



*Type:*
null or path



*Default:*
` null `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.keys\.\<name>\.name



File name of the key\.



*Type:*
string



*Default:*
` "‹name›" `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.keys\.\<name>\.permissions



Permissions to set for the file\.



*Type:*
string



*Default:*
` "0600" `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.keys\.\<name>\.text



Content of the key\.
One of ` text `, ` keyCommand ` and ` keyFile ` must be set\.



*Type:*
null or string



*Default:*
` null `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.keys\.\<name>\.uploadAt



When to upload the keys\.

 - pre-activation (default): Upload the keys before activating the new system profile\.
 - post-activation: Upload the keys after successfully activating the new system profile\.

For ` colmena upload-keys `, all keys are uploaded at the same time regardless of the configuration here\.



*Type:*
one of “pre-activation”, “post-activation”



*Default:*
` "pre-activation" `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.keys\.\<name>\.user



The group that will own the file\.



*Type:*
string



*Default:*
` "root" `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.privilegeEscalationCommand



Command to use to elevate privileges when activating the new profiles on SSH hosts\.

This is used on SSH hosts when ` deployment.targetUser ` is not ` root `\.
The user must be allowed to use the command non-interactively\.



*Type:*
list of string



*Default:*

```
[
  "sudo"
  "-H"
  "--"
]
```

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.replaceUnknownProfiles



Allow a configuration to be applied to a host running a profile we
have no knowledge of\. By setting this option to false, you reduce
the likelyhood of rolling back changes made via another Colmena user\.

Unknown profiles are usually the result of either:

 - The node had a profile applied, locally or by another Colmena\.
 - The host running Colmena garbage-collecting the profile\.

To force profile replacement on all targeted nodes during apply,
use the flag ` --force-replace-unknown-profiles `\.



*Type:*
boolean



*Default:*
` true `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.tags



A list of tags for the node\.

Can be used to select a group of nodes for deployment\.



*Type:*
list of string



*Default:*
` [ ] `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.targetHost



The target SSH node for deployment\.

By default, the node’s attribute name will be used\.
If set to null, only local deployment will be supported\.



*Type:*
null or string



*Default:*
` "{hostname}" `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.targetPort



The target SSH port for deployment\.

By default, the port is the standard port (22) or taken
from your ssh_config\.



*Type:*
null or unsigned integer, meaning >=0



*Default:*
` null `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## colmena\.deployment\.targetUser



The user to use to log into the remote node\. If set to null, the
target user will not be specified in SSH invocations\.



*Type:*
null or string



*Default:*
` "root" `

*Declared by:*
 - [NixOs-Staged-Hive/modules/colmena\.nix](../modules/colmena.nix)



## gateway



TODO:



*Type:*
string

*Declared by:*
 - [NixOs-Staged-Hive/modules/network\.nix](../modules/network.nix)



## interface



Sets this interface to be used for network configuration\.

TODO:



*Type:*
string



*Example:*
` "ens1" `

*Declared by:*
 - [NixOs-Staged-Hive/modules/network\.nix](../modules/network.nix)



## ip



TODO: describe the interplay with kubernetes module



*Type:*
string



*Example:*
` "\"dhcp\" or \"192.168.0.1" `

*Declared by:*
 - [NixOs-Staged-Hive/modules/network\.nix](../modules/network.nix)



## k3s\.agent\.ip



null



*Type:*
null or string



*Default:*
` null `

*Declared by:*
 - [NixOs-Staged-Hive/modules](../modules)



## k3s\.agent\.name



null



*Type:*
null or string



*Default:*
` null `

*Declared by:*
 - [NixOs-Staged-Hive/modules](../modules)



## k3s\.init\.ip



null



*Type:*
null or string



*Default:*
` null `

*Declared by:*
 - [NixOs-Staged-Hive/modules](../modules)



## k3s\.server\.extraConfig



null



*Type:*
null or path



*Default:*
` null `

*Declared by:*
 - [NixOs-Staged-Hive/modules](../modules)



## k3s\.server\.ip



null



*Type:*
null or string



*Default:*
` null `

*Declared by:*
 - [NixOs-Staged-Hive/modules](../modules)



## k3s\.server\.manifests



null



*Type:*
list of path



*Default:*
` [ ] `

*Declared by:*
 - [NixOs-Staged-Hive/modules](../modules)



## k3s\.server\.name



null



*Type:*
null or string



*Default:*
` null `

*Declared by:*
 - [NixOs-Staged-Hive/modules](../modules)



## k3s\.version



FIXME: depricated; should be removed



*Type:*
string

*Declared by:*
 - [NixOs-Staged-Hive/modules](../modules)



## netmask



TODO:



*Type:*
signed integer

*Declared by:*
 - [NixOs-Staged-Hive/modules/network\.nix](../modules/network.nix)



## partitioning\.enable_disko



If set to true the ` config.disko ` option (see [disko docs](https://github\.com/nix-community/disko/blob/master/docs/INDEX\.md)) will be set based on the ` partitioning.format_disko ` and ` partitioning.additional_disko ` options from this module\.
This will generate a file system configuration according to the disko options\.
If this option is disabled the disko option is not set and the file system configuration has to be defined another way\.



*Type:*
boolean



*Default:*
` false `

*Declared by:*
 - [NixOs-Staged-Hive/modules/partitioning\.nix](../modules/partitioning.nix)



## partitioning\.additional_disko



This disko definitions will be used in addition to the formatting definition to build the whole disko definition for mounting configuration (see [disko docs](https://github\.com/nix-community/disko/blob/master/docs/INDEX\.md))\.
Additionally a script with the combined configuration from ` partitioning.format_disko ` and ` partitioning.additional_disko ` will be created\.
The script will be added to ` $PATH ` and executable with ` disko-format-ALL `\.
It will not be executed with the ` setup ` script



*Type:*
attribute set



*Default:*
` { } `



*Example:*

```
{
  devices = {
    disk = {
      other = {
        content = {
          partitions = {
            data = {
              content = {
                format = "ext4";
                mountpoint = "/var/data";
                type = "filesystem";
              };
              size = "100%";
            };
          };
          type = "gpt";
        };
        device = "/dev/disk/by-id/virtio-WINDOWS";
        type = "disk";
      };
    };
  };
}
```

*Declared by:*
 - [NixOs-Staged-Hive/modules/partitioning\.nix](../modules/partitioning.nix)



## partitioning\.format_disko



This disko definitions will be used to build a formating script and for the systems mounting configuration (see [disko docs](https://github\.com/nix-community/disko/blob/master/docs/INDEX\.md))\.
The script will be added to ` $PATH ` and executable with ` disko-format `\.
It will be executed running the ` setup ` script (but can be skipped)\.



*Type:*
attribute set



*Default:*
` { } `



*Example:*

```
{
  devices = {
    disk = {
      nixos = {
        content = {
          partitions = {
            boot = {
              content = {
                format = "vfat";
                mountpoint = "/boot";
                type = "filesystem";
              };
              size = "512M";
              type = "EF00";
            };
            root = {
              content = {
                format = "ext4";
                mountpoint = "/";
                type = "filesystem";
              };
              size = "100%";
            };
          };
          type = "gpt";
        };
        device = "/dev/disk/by-id/virtio-OS";
        type = "disk";
      };
    };
  };
}
```

*Declared by:*
 - [NixOs-Staged-Hive/modules/partitioning\.nix](../modules/partitioning.nix)



## setup\.bootLoader\.customConfig



Custom configuration for the nixOs ` boot.loader ` options used in the mini system\.

The boot configuration for the mini system has to function\. By default (if this option is ` null `) specific options from your configuration (see ` scripts/boot-crawler.nix `) are copied to the ` boot.loader ` configuration of the generated mini system\.
If this behavior does not work for you, you can set this option to be copied instead\.



*Type:*
null or (attribute set)



*Default:*
` null `



*Example:*

```
{
  grub = {
    extraConfig = "smth smth";
  };
}
```

*Declared by:*
 - [NixOs-Staged-Hive/modules/setup\.nix](../modules/setup.nix)



## setup\.files



Files that should be availabe during the installation phase\.
These files will be copied to /etc/nixos/files\.
TODO: Check if folders work out of the box as well\.



*Type:*
list of path



*Default:*
` [ ] `

*Declared by:*
 - [NixOs-Staged-Hive/modules/setup\.nix](../modules/setup.nix)



## setup\.postScript



A set of shell commands that are executed after the setup instructions are started in the installation iso\.

The commands will be concatenated to a script which will be exported in /bin in the installation iso as ` post-setup `\.
During the post-script phase the hardware-configuration was already generated and all nioxos files are both in /etc/nixos and in /mnt/etc/nixos\.
The script will not be present after the installation nor in the final machine config\.



*Type:*
list of string



*Default:*
` [ ] `



*Example:*

```
[
  "sudo poweroff"
]
```

*Declared by:*
 - [NixOs-Staged-Hive/modules/setup\.nix](../modules/setup.nix)



## setup\.preScript



A set of shell commands that are executed before the setup instructions are started in the installation iso\.

The commands will be concatenated to a script which will be exported in /bin in the installation iso as ` pre-setup `\.
During the pre-script phase the hardware-configuration was NOT generated and all nioxos files are still only in /etc/nixos\.
The script will not be present after the installation nor in the final machine config\.



*Type:*
list of string



*Default:*
` [ ] `



*Example:*

```
[
  "echo 'hello setup'"
]
```

*Declared by:*
 - [NixOs-Staged-Hive/modules/setup\.nix](../modules/setup.nix)



## setup\.scripts



Files that should be available as executable scripts during the installation phase\.

These files will be turned into a derivation by ` pkgs.writeScriptBin ` and added
to ` environment.systemPackages ` with the basename of the given path as script name\.
This means that they will be in ` $PATH ` and executable by name\.



*Type:*
list of path



*Default:*
` [ ] `



*Example:*
` <derivation greetings> `

*Declared by:*
 - [NixOs-Staged-Hive/modules/setup\.nix](../modules/setup.nix)



## subnet



TODO:



*Type:*
string

*Declared by:*
 - [NixOs-Staged-Hive/modules/network\.nix](../modules/network.nix)


