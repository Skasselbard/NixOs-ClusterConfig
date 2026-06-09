{
  pkgs,
  flakePkgs,
  ...
}:

let
  guestName = "testvm";
  guestMac = "02:00:00:00:00:01";
  guestVsockCid = 3;
  guestVsockSshPort = 5000;
  intrerface = "enp42s0";
  natInterface = "microvm";
in
{
  
  
  networking.nat = {
    enable = true;
  
    externalInterface = intrerface;
    # The bridge where you want to provide Internet access
    internalInterfaces = [ natInterface ];
  };


  microvm.vms."${guestName}" = {

    extraModules = [
    ];

    config = {
      users.users.root.initialPassword = "root";

      microvm = {
        hypervisor = "qemu";
        vsock.cid = guestVsockCid;

        vcpu = 2;
        mem = 4096;

        interfaces = [
          {
            type = "tap";
            id = natInterface;
            mac = guestMac;
          }
        ];

        shares = [
          {
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            tag = "ro-store";
            proto = "virtiofs";
          }
        ];
      };

      networking.hostName = "agent-vm";
      # networking.hosts."10.0.2.2" = [
      #   "host.internal"
      #   "host.qemu"
      # ];
      # networking.useNetworkd = true;
      # networking.firewall.allowedTCPPorts = [ 22 ];

      systemd.network.enable = true;
      # systemd.network.networks."10-uplink" = {
      #   matchConfig.Type = "ether";
      #   networkConfig = {
      #     DHCP = "yes";
      #     IPv6AcceptRA = true;
      #   };
      #   dhcpV4Config = {
      #     RouteMetric = 100;
      #     UseDNS = true;
      #   };
      #   linkConfig.RequiredForOnline = "routable";
      # };

      services.getty.autologinUser = "root";
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "yes";
          PasswordAuthentication = true;
          KbdInteractiveAuthentication = false;
        };
      };

      # systemd.services.ssh-over-vsock = {
      #   description = "Expose guest SSH over VSOCK";
      #   after = [ "sshd.service" ];
      #   wants = [ "sshd.service" ];
      #   wantedBy = [ "multi-user.target" ];
      #   serviceConfig = {
      #     ExecStart = "${pkgs.socat}/bin/socat VSOCK-LISTEN:${toString guestVsockSshPort},fork,reuseaddr TCP:127.0.0.1:22";
      #     Restart = "always";
      #     RestartSec = 1;
      #   };
      # };

      system.stateVersion = "25.11";
    };
  };
}
