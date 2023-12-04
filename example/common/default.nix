{ pkgs, lib, config, ... }: {

  imports = [ ../bin/modules ];

  admin.name = "admin";
  admin.sshKeys =
    [ (builtins.readFile "${builtins.getEnv "HOME"}/.ssh/id_rsa.pub") ];
  # tarball-ttl = 0;
}
