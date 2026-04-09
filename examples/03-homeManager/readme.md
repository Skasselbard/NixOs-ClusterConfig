# Home Manager Example

Configure per-user environments using [Home Manager](https://github.com/nix-community/home-manager) modules assigned at the cluster level.

This example adds an `admin` user with a customized shell prompt (starship) alongside the existing `root` user.

## What You Will Learn

- How to assign Home Manager modules to cluster users
- The `home.stateVersion` requirement when using Home Manager
- How to override the Home Manager version used by ClusterConfig
- Using `colmena` for deploying configuration updates

## Prerequisites

- Three VMs already deployed from [Example 01](../01-simpleCluster/)
- The SSH private key added to your SSH agent:

  ```bash
  ssh-add ../00-exampleConfigs/secrets/sshKey
  ```

## Key Concepts

### Home Manager modules per user

Each cluster user can have a `homeManagerModules` list. These are standard Home Manager modules (files with `_class = "homeManager"`) that configure the user's environment (shell, programs, dotfiles, etc.).

### The `home.stateVersion` requirement

**Important:** Once ANY user in a cluster uses Home Manager, ALL users must include a module that sets `home.stateVersion`. The [default module](../00-exampleConfigs/homeManager/default.nix) in this example does exactly that:

```nix
{
  _class = "homeManager";
  home.stateVersion = "24.05";
  programs.home-manager.enable = false;
}
```

### Overriding the Home Manager version

ClusterConfig bundles its own Home Manager input. If your nixpkgs version differs, override it with `inputs.home-manager.follows`:

```nix
clusterConfigFlake = {
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.follows = "home-manager";  # Use our version
  url = "github:Skasselbard/NixOs-ClusterConfig";
};
```

## Result

Three VMs with two cluster users deployed on all machines:

| User | Home Manager Config | Shell Prompt |
| --- | --- | --- |
| `root` | Default module only (`home.stateVersion`) | Standard bash prompt |
| `admin` | Default + [starship](../00-exampleConfigs/homeManager/starship.nix) | Colored starship prompt |

## Deployment

Since the machines are already installed (from Example 01), use **colmena** to push the updated configuration:

```bash
nix run .#colmena apply
```

This deploys all machines from all clusters in the flake. Without additional flags, it deploys everything.

Alternatively, deploy machines individually:

```bash
nix run .#example.vm0.deploy
nix run .#example.vm1.deploy
nix run .#example.vm2.deploy
```

Or use the helper script: `bash deploy.sh`

## Test

1. Connect as root — you should see the default bash prompt:

   ```bash
   ssh root@192.168.122.200
   ```

2. Connect as admin — you should see a colored starship prompt:

   ```bash
   ssh admin@192.168.122.200
   ```

> **Tip:** You may need [Nerd Fonts](https://www.nerdfonts.com/) installed on your local machine to display all starship symbols correctly.

## What's Next

- [Example 04](../04-secretDeployment/) — deploying encrypted secrets to machines