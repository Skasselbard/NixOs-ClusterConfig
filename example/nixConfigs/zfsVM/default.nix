{
  imports = [ ../../common ./partitioning.nix ];
  # generated with `mkpasswd -m sha-512 test` so the password is `test`
  admin.hashedPwd =
    "$6$uKucbDFAx$jheR2LeYE45YB6.pQKQJuVuVVCZr/rab/MKUCTa.U1VFZLsJxBcDtJrF4xultum.AHXneNwppm57qxoMdxdJv1";
  networking.hostName = "zfsVM";
  ip = "dhcp";
  interface = "ens3";
  colmena.deployment = {
    targetHost = "192.168.122.14";
    tags = [ "vm" ];
  };
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
