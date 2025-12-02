{
  imports = [
    ./etcd.nix
    ./api-server.nix
    ./controller-manager.nix
    ./scheduler.nix
    ./haProxy.nix
    ./keepalived.nix
  ];
}
