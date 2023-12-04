mkdir -p bin
wget -qO- https://github.com/Skasselbard/NixOS-Staged-Hive/archive/master.tar.gz | tar xvz --strip-components=1  -C bin

echo '#!/bin/bash

ROOT=$PWD
CMD="nixos-staged-hive -p $ROOT ${@:1}"
cd bin
nix-shell --run "$CMD"
' > nixos-staged-hive

chmod +x nixos-staged-hive

./nixos-staged-hive setup