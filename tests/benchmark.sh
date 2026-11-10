#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export NIX_SHOW_STATS=1
for nodes in 1 4 8; do
  echo "=== ${nodes} nodes, all DNS configurations ===" >&2
  time nix eval --offline --impure --no-write-lock-file --option eval-cache false --json --expr "
    let
      f = builtins.getFlake \"path:$root\";
      names = builtins.genList (i: \"node\" + toString i) $nodes;
      machines = builtins.listToAttrs (map (name: {
        inherit name;
        value = {
          system = \"x86_64-linux\";
          nixosModules = [{ system.stateVersion = \"25.05\"; networking.interfaces.eth0.ipv4.addresses = [{ address = \"192.0.2.1\"; prefixLength = 24; }]; }];
        };
      }) names);
      c = f.lib.buildCluster {
        modules = [ f.clusterConfigModules.simple-dns ];
        domain = { suffix = \"example.com\"; clusters.lab = {
          inherit machines;
          services.dns = { selectors = [ f.lib.filters.clusterMachines ]; roles.hosts = [ f.lib.filters.clusterMachines ]; };
        }; };
      };
    in map (name: c.nixosConfigurations.\"lab-\${name}\".config.networking.extraHosts) names
  " >/dev/null
done