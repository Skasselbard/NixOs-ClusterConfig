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
