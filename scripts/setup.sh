#!/bin/sh

echo "Executing setup pre-script"
pre-setup
echo "Finished executing setup pre-script"

set -e
echo "NixOS installation needs sudo privileges."
sudo echo ""

# wait for dns service startup
timeout 1m bash -c 'until [ "$(dig +short -t srv _ldap._tcp.google.com.)" ]; do sleep 5; done' || echo "Error: cannot resolve google.com"

nixos_version=$(cat /etc/nixos/version)

# copy configs
sudo mkdir -p /mnt/etc/nixos
sudo nixos-generate-config --root /mnt --no-filesystems
sudo cp -LR /etc/nixos /mnt/etc

cd /mnt
# https://github.com/NixOS/nixpkgs/blob/master/nixos/doc/manual/man-nixos-install.xml
sudo nixos-install --no-root-passwd -I nixpkgs="https://github.com/NixOS/nixpkgs/archive/$nixos_version.tar.gz"

echo "Executing setup post-script"
post-setup
echo "Finished executing setup post-script"