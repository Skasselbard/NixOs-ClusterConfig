{ pkgs ? import <nixpkgs> { }, lib ? import <nixpkgs/lib>, host-definition, ...
}:

let
  eval = (lib.evalModules {
    modules = [
      host-definition
      # Set an arbitrary host platform. The queried options are independent 
      # from our the plattform since we only look up our own modules.
      { nixpkgs.hostPlatform = "x86_64-linux"; }
    ] ++ (import <nixpkgs/nixos/modules/module-list.nix>);
  });
in {
  config = {
    # networking.interfaces.ens3 = eval.config.networking.ens3;
    admin = eval.config.admin;
    hostname = eval.config.networking.hostName;
    interface = eval.config.interface;
    ip = eval.config.ip;
    # gateway = config.networking.defaultGateway;
    # interfaces = config.networking.interfaces;
    # k3s = {
    #   init.ip
    #   server.ip
    #   server.name
    #   agent.ip
    #   agent.name
    #   version
    # }
    # nixos_version
    # targetHost
  };
}
