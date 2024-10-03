nix run .#machines.vm0.deploySecrets
nix run .#machines.vm1.deploySecrets
nix run .#machines.vm2.deploySecrets
nix run .#machines.vm0.deploy
nix run .#machines.vm1.deploy
nix run .#machines.vm2.deploy