{
  config.extensions.clusterServices.dns = {
    defaultModule = import ./staticDns.nix;
    roles = [ "hosts" ];
  };
}
