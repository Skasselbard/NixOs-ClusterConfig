{ pkgs, lib, config, ... }: {
  imports = [ ../../common ./partitioning.nix ];

  # generated with `mkpasswd -m sha-512 test` so the password is `test`
  admin.hashedPwd =
    "$6$uKucbDFAx$jheR2LeYE45YB6.pQKQJuVuVVCZr/rab/MKUCTa.U1VFZLsJxBcDtJrF4xultum.AHXneNwppm57qxoMdxdJv1";
  networking.hostName = "simpleVM";
  ip = "dhcp";
  interface = "ens3"; # depends on your vm configuration
  colmena.deployment = {
    targetHost = "192.168.122.14"; # depends on your hypervisor configuration
    tags = [ "vm" ];
  };

  # Delete this if you use legacy boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
