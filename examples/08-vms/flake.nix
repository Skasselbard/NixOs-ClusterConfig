{
  inputs = {

    # Import nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Import Home Manager.
    # The Home Manager version should match your nixpkgs channel (25.05 → release-25.05).
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Import the ClusterConfig flake.
    clusterConfigFlake = {
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      # url = "github:Skasselbard/NixOs-ClusterConfig";
      url = "path:../../";
    };

    # Import disko for declarative disk partitioning
    disko = {
      url = "github:nix-community/disko/v1.13.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Import impernance to manage persistent data on microvm
    impermanence.url = "github:nix-community/impermanence";

  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      clusterConfigFlake,
      impermanence,
      ...
    }:

    let # --- Imports and definitions ---

      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      filters = clusterConfigFlake.lib.filters;

      # Shared configuration (machines, secrets, Home Manager modules)
      configurations = (import ../00-exampleConfigs) { inherit pkgs; };
      secrets = configurations.secrets;
      machines = configurations.machines;
      homeModules = configurations.homeModules;

      #####################################################
      # ClusterConfig
      #####################################################
      clusterConfig = clusterConfigFlake.lib.buildCluster {

        modules = [
          clusterConfigFlake.clusterConfigModules.default
          clusterConfigFlake.clusterConfigModules.simple-dns
        ];

        domain = {
          suffix = "com";

          clusters = {

            example = {

              #############################################
              # Services
              services = {
                dns = {
                  roles.hosts = [ filters.clusterMachines ];
                  selectors = [ filters.clusterMachines ];
                };
              };

              ############################################
              # Users
              #
              users = {

                root = {
                  homeManagerModules = [ homeModules.default ];

                  systemConfig = {
                    extraGroups = [ "wheel" ];
                    hashedPassword = secrets.pswdHash.root;
                    openssh.authorizedKeys.keys = [ secrets.ssh.publicKey ];
                  };
                };

                admin = {
                  homeManagerModules = [
                    homeModules.default
                    homeModules.starship
                  ];

                  systemConfig = {
                    isNormalUser = true; # Creates a regular (non-root) user with a home directory
                    extraGroups = [ "wheel" ];
                    hashedPassword = secrets.pswdHash.admin;
                    openssh.authorizedKeys.keys = [ secrets.ssh.publicKey ];
                  };
                };
              };

              ############################################
              # Machines
              machines = {

                vm0 = {
                  inherit system;
                  deployment = {
                    targetHost = "192.168.122.200";
                  };
                  nixosModules = [
                    machines.vm0
                    inputs.disko.nixosModules.default
                    ../00-exampleConfigs/machines/hm-bug-workaround.nix
                  ];
                };

                vm1 = {
                  inherit system;
                  deployment = {
                    targetHost = "192.168.122.201";
                  };
                  nixosModules = [
                    machines.vm1
                    inputs.disko.nixosModules.default
                    ../00-exampleConfigs/machines/hm-bug-workaround.nix
                  ];
                };

                vm2 = {
                  inherit system;
                  deployment = {
                    targetHost = "192.168.122.202";
                  };
                  nixosModules = [
                    machines.vm2
                    inputs.disko.nixosModules.default
                    ../00-exampleConfigs/machines/hm-bug-workaround.nix
                  ];
                };

              };

              ############################################
              # Virtual Machines (VMs)
              #
              # VMs are defined alongside machines under `domain.clusters.<name>.vms`.
              # They participate in all cluster features: services, users, filters,
              # and the clusterConfig representation.
              #
              # Each VM has a `host` field pointing to an existing machine by its FQDN
              # (e.g., "vm0.example.com"). The VM module automatically:
              #   1. Resolves the host to find the machine
              #   2. Enables microvm.host on that machine (no manual config needed)
              #   3. Evaluates the VM's NixOS config
              #   4. Injects it into the host under microvm.vms.<name>.evaluatedConfig
              #
              # VMs are NOT deployed separately — they are part of the host's NixOS
              # configuration. Deploying the host also updates its VMs.
              #
              # Key options:
              #   host             — FQDN of the host machine (required)
              #   autostart        — start VM at host boot (default: true)
              #   restartIfChanged — restart VM when host config changes (default: true)
              #   backend.type     — backend discriminator (only "microvm" currently)
              #   backend.microvm  — microvm.nix-specific options
              #   nixosModules     — NixOS modules for the VM guest
              vms = {

                # ── microVm0: hosted on vm0 ──
                microVm0 =
                  let
                    guestName = "microVm0";
                    mac = "02:00:00:00:00:10";
                  in
                  {
                    inherit system;

                    # ── Host binding ──
                    # The FQDN of the machine that hosts this VM.
                    # "vm0.example.com" resolves to machine "vm0" in cluster "example"
                    # (with domain suffix "com"). Partial FQDNs are also accepted:
                    # "vm0.example" would resolve the same way.
                    host = "vm0.example.com";

                    # Automatically start this VM when the host boots.
                    autostart = true;

                    # Restart the VM's systemd service when the host is rebuilt
                    # and the VM's configuration has changed.
                    restartIfChanged = true;

                    # ── Backend: microvm.nix ──
                    # All options under backend.microvm are imported directly from the
                    # microvm.nix flake and stay in sync with upstream changes.
                    backend.microvm = {
                      # Hypervisor to use: "qemu" (default) or other microvm hypervisors.
                      hypervisor = "qemu";

                      # Virtual hardware resources.
                      vcpu = 2; # Number of virtual CPUs
                      mem = 4096; # Memory in MB

                      # ── Network interfaces ──
                      # Defines the virtual NIC seen by the VM guest.
                      #   type = "user"    — user-mode NAT networking (no external setup needed)
                      #   type = "tap"     — bridged networking (requires host bridge setup)
                      #   type = "macvtap" — direct MAC association (requires host config)
                      #   type = "bridge"  — attach to a host bridge
                      #
                      # With "user" mode, the VM gets a private IP (typically 10.0.2.x)
                      # and access to outside networks via the host's IP.
                      # Use forwardPorts to expose VM services on the host.
                      interfaces = [
                        {
                          type = "user";
                          id = "qemu"; # Interface identifier (shows up in QEMU)
                          mac = mac; # Custom MAC address (optional, auto-generated if omitted)
                        }
                      ];

                      # ── Port forwarding (user-mode networking only) ──
                      # Forwards ports from the host to the VM.
                      # Required for SSH access when using "user" mode interfaces
                      # since the VM is behind NAT.
                      forwardPorts = [
                        {
                          from = "host"; # Forward from the host side
                          host.port = 2222; # Port on the host machine
                          guest.port = 22; # Port inside the VM (SSH)
                        }
                      ];

                      # ── shareNixStore convenience option ──
                      # When true (default), adds a 9p/virtiofs share of the host's
                      # /nix/store at /nix/.ro-store inside the VM, so the VM can
                      # reuse the host's store instead of duplicating it.
                      # Set to false if you want a fully isolated store.
                      shareNixStore = true;

                      # ── Persistent volumes ──
                      # Virtual disk images attached to the VM. These persist across
                      # reboots and are used together with impermanence (see nixosModules)
                      # to keep stateful data like SSH host keys.
                      volumes = [
                        {
                          # Filename (stored relative to the microvm state directory).
                          image = "${guestName}-system-config.img";
                          size = 256; # Size in MB
                          label = "system-config"; # Filesystem label (optional, used by the guest)
                        }
                      ];
                    };

                    # ── VM guest NixOS configuration ──
                    # Standard NixOS modules that define what runs inside the VM.
                    # These use the same module system as machine configurations.
                    nixosModules = [
                      # Import the impermanence module for state persistence.
                      # MicroVMs reset their root filesystem on every boot by default,
                      # so any state that must survive reboots needs explicit handling.
                      impermanence.nixosModules.impermanence

                      ../00-exampleConfigs/machines/hm-bug-workaround.nix

                      # Inline NixOS module configuring the VM guest.
                      {
                        # Mount the persistent volume created by backend.microvm.volumes.
                        # The device name matches the label set on the volume.
                        fileSystems."/persistence/system" = {
                          device = "/dev/disk/by-label/system-config";
                          fsType = "ext4";
                          neededForBoot = true; # Mount before services start
                        };

                        # Impermanence: selectively persist files and directories
                        # from the volatile root to the persistent volume.
                        environment.persistence."/persistence/system" = {
                          # Persist machine ID and user/group IDs across reboots.
                          directories = [
                            "/var/lib/nixos"
                          ];
                          # Persist SSH host keys so the VM's fingerprint doesn't
                          # change on every boot (useful for debugging; in production
                          # with multiple service ports this may be less critical).
                          files = [
                            "/etc/ssh/ssh_host_ed25519_key"
                            "/etc/ssh/ssh_host_ed25519_key.pub"
                            "/etc/ssh/ssh_host_rsa_key"
                            "/etc/ssh/ssh_host_rsa_key.pub"
                          ];
                        };

                        # Enable SSH for debugging and management.
                        services.openssh = {
                          enable = true;
                          settings = {
                            PermitRootLogin = "yes"; # Allow root login for debugging
                          };
                        };
                        networking.firewall.allowedTCPPorts = [ 22 ];

                        system.stateVersion = "26.05";
                      }
                    ];

                  };

                # ── microVm1: hosted on vm1 (same structure as microVm0) ──
                microVm1 =
                  let
                    guestName = "microVm1";
                    mac = "02:00:00:00:00:11";
                  in
                  {
                    inherit system;

                    host = "vm1.example.com";
                    autostart = true;
                    restartIfChanged = true;

                    backend.microvm = {
                      hypervisor = "qemu";
                      vcpu = 2;
                      mem = 4096;
                      interfaces = [
                        {
                          type = "user";
                          id = "qemu";
                          mac = mac;
                        }
                      ];
                      forwardPorts = [
                        {
                          from = "host";
                          host.port = 2222;
                          guest.port = 22;
                        }
                      ];
                      shareNixStore = true;
                      volumes = [
                        {
                          image = "${guestName}-system-config.img";
                          size = 256;
                          label = "system-config";
                        }
                      ];
                    };

                    nixosModules = [
                      impermanence.nixosModules.impermanence
                      ../00-exampleConfigs/machines/hm-bug-workaround.nix
                      {
                        fileSystems."/persistence/system" = {
                          device = "/dev/disk/by-label/system-config";
                          fsType = "ext4";
                          neededForBoot = true;
                        };
                        environment.persistence."/persistence/system" = {
                          directories = [ "/var/lib/nixos" ];
                          files = [
                            "/etc/ssh/ssh_host_ed25519_key"
                            "/etc/ssh/ssh_host_ed25519_key.pub"
                            "/etc/ssh/ssh_host_rsa_key"
                            "/etc/ssh/ssh_host_rsa_key.pub"
                          ];
                        };
                        services.openssh = {
                          enable = true;
                          settings.PermitRootLogin = "yes";
                        };
                        networking.firewall.allowedTCPPorts = [ 22 ];
                        system.stateVersion = "26.05";
                      }
                    ];

                  };
              };

            };

          };

        };
      };

    in
    # IMPORTANT: Return the clusterConfig directly as the flake output.
    clusterConfig;
}
