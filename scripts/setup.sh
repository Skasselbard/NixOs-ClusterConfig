#!/bin/sh

# wait for dns service startup
timeout 1m bash -c 'until [ "$(dig +short -t srv _ldap._tcp.google.com.)" ]; do sleep 5; done' || echo "Error: cannot resolve google.com"

set -e
echo "NixOS installation needs sudo privileges."
sudo echo ""

echo "Executing setup pre-scripts"
pre-setup
echo "Finished executing setup pre-scripts"

# initialize directories
sudo mkdir -p /mnt/etc/nixos
sudo nixos-generate-config --root /mnt --no-filesystems
sudo cp -LR /etc/nixos /mnt/etc

cd /mnt
# https://github.com/NixOS/nixpkgs/blob/master/nixos/doc/manual/man-nixos-install.xml
sudo nixos-install --no-root-passwd -I nixpkgs="https://github.com/NixOS/nixpkgs/archive/$(nixos_version).tar.gz"

echo "Executing setup post-scripts"
post-setup
echo "Finished executing setup post-scripts"