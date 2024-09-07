{ pkgs, ... }:
let osDevicePath = "/dev/disk/by-id/virtio-OS";
in {
  secrets = import ./secrets;

  machines = {

    vm0 = (import ./machines/vm.nix) {
      inherit osDevicePath;
      ip = "192.168.122.200";
    };

    vm1 = (import ./machines/vm.nix) {
      inherit osDevicePath;
      ip = "192.168.122.201";
    };

    vm2 = (import ./machines/vm.nix) {
      inherit osDevicePath;
      ip = "192.168.122.202";
    };

  };

  homeModules = {
    default = import ./homeManager/default.nix;
    starship = (import ./homeManager/starship.nix) { inherit pkgs; };
  };

}
