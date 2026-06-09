{
  password ? "root",
  vcpu ? 2,
  mem ? 4096,
  mac,
}:
{
  vmConfig = {
    users.users.root.initialPassword = password;

    microvm = {
      hypervisor = "qemu";

      inherit vcpu mem;

      interfaces = [
        {
          inherit mac;
          type = "user";
          id = "qemu";
        }
      ];

      forwardPorts = [
        {
          from = "host";
          host.port = 2222;
          guest.port = 22;
        }
      ];

    };

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "yes";
      };

    };
    networking.firewall.allowedTCPPorts = [ 22 ];

    system.stateVersion = "26.05";
  };
}
