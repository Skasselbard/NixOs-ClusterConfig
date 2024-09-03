let osDevicePath = "/dev/disk/by-id/virtio-OS";
in {
  secrets = import ./secrets;

  machines = {

    vm0 = (import ./machines/vm.nix) {
      inherit osDevicePath;
      ip = "192.168.100.10";
    };

    vm1 = (import ./machines/vm.nix) {
      inherit osDevicePath;
      ip = "192.168.100.11";
    };

    vm2 = (import ./machines/vm.nix) {
      inherit osDevicePath;
      ip = "192.168.100.12";
    };

  };

}
