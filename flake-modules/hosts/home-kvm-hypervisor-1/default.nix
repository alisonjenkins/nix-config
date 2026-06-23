{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
in {
  flake.nixosConfigurations.home-kvm-hypervisor-1 = lib.nixosSystem {
    specialArgs = {
      username = "ali";
      inherit inputs;
      inherit (self) outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }

      # Custom modules via flake outputs
      self.nixosModules.locale
      self.nixosModules.base
      self.nixosModules.nohang
      self.nixosModules.servers
      self.nixosModules.libvirtd
      self.nixosModules.home-kvm-hypervisor-1-hardware
      self.nixosModules.home-kvm-hypervisor-1-disko-config

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.nixvirt.nixosModules.default
      inputs.sops-nix.nixosModules.sops

      # Host-specific configuration
      ({ inputs, lib, outputs, pkgs, ... }: {
        modules.nohang = {
          enable = true;
          extraProtectedProcesses = [ "libvirtd" "qemu-system-x86_64" ];
        };
        modules.base = {
          enable = true;
          bootLoader = "grub";
        };
        modules.libvirtd.enable = true;
        modules.locale.enable = true;
        modules.servers = {
          enable = true;
          prometheus.smartctlExporter.enable = true;
          prometheus.libvirtExporter.enable = true;
          lokiPush.enable = true;
        };

        # Silence mdadm warning: mdmon needs MAILADDR or PROGRAM set or it
         # crashes. Local root mail is enough — we don't have an MTA configured.
        boot.swraid.mdadmConf = ''
          MAILADDR root
        '';

        # Upstream prometheus-libvirt-exporter (2.3.3) lacks meta.mainProgram
        # in our pinned nixpkgs (already added in nixos-unstable HEAD). Local
        # override silences the getExe warning until the next nixpkgs bump.
        nixpkgs.overlays = [
          (_final: prev: {
            prometheus-libvirt-exporter = prev.prometheus-libvirt-exporter.overrideAttrs (old: {
              meta = (old.meta or { }) // { mainProgram = "libvirt-exporter"; };
            });
          })
        ];

        boot = {
          kernelPackages = pkgs.linuxPackages_latest;

          # This board boots GRUB purely via the EFI removable/fallback path
          # (\EFI\BOOT\BOOTX64.EFI on each RAID1 ESP member); there is no
          # persistent "nixos" NVRAM boot entry. The firmware rejects
          # efibootmgr NVRAM writes ("Operation not permitted"), so the base
          # module's canTouchEfiVariables=true made every deploy's grub-install
          # exit non-zero even though grub.cfg updated fine. Install as
          # removable and stop touching EFI variables to match reality.
          loader = {
            efi.canTouchEfiVariables = lib.mkForce false;
            grub.efiInstallAsRemovable = lib.mkForce true;
          };

          kernelParams = [
            # SAS3008 controllers (1000:0097) bound early via vfio-pci — prevents mpt3sas from claiming them
            # GPU (1002:164e) stays on amdgpu for LUKS prompt; libvirt rebinds it when VM starts (managed='yes')
            "vfio-pci.ids=1000:0097"
            "systemd.gpt_auto=no"
          ];

          kernel = {
            sysctl = {
              "net.ipv4.conf.all.forwarding" = true;
              "net.ipv6.conf.all.forwarding" = true;

              # Bound dirty (un-flushed) page-cache in absolute bytes instead of
              # the default ratios. dirty_ratio=20 on a 30.5 GiB host lets ~6 GiB
              # of dirty pages accumulate before a writer blocks — on a host
              # where ~22 GiB is mlock-pinned by passthrough VMs that spike
              # competes for the little remaining RAM. Cap at 1 GiB / 256 MiB bg.
              # bytes and ratio are mutually exclusive, so the base ratios MUST
              # be forced to 0 or the kernel keeps using them.
              "vm.dirty_bytes" = 1073741824;            # 1 GiB
              "vm.dirty_background_bytes" = 268435456;  # 256 MiB
              "vm.dirty_ratio" = lib.mkForce 0;
              "vm.dirty_background_ratio" = lib.mkForce 0;

              # Push cold anonymous pages of the swappable tenants (download +
              # storage VMs, host daemons) into zram aggressively to free real
              # RAM — frees ~2 GiB. The pinned jellyfin VM is exempt (its RAM is
              # mlock'd, unswappable at any swappiness). page-cluster=0 reads one
              # page per swap-in: zram is random-access RAM, so the default
              # 8-page readahead just wastes work.
              "vm.swappiness" = 100;
              "vm.page-cluster" = 0;
            };
          };

          initrd = {
            availableKernelModules = [
              "ixgbe"
              "mt7921e"
              "r8169"
            ];
            # Bypass kernel workqueues for dm-crypt — significant
            # NVMe I/O improvement on a CPU with hardware AES (the
            # actual crypto is near-free; the workqueue latency
            # was dominating). Runtime-only, applies on next boot.
            luks.devices.os_raid1_crypt.crypttabExtraOpts = [
              "no-read-workqueue"
              "no-write-workqueue"
            ];
          };
        };

        console.keyMap = "us";

        environment = {
          pathsToLink = [ "/share/zsh" ];

          variables = {
            PATH = [
              "\${HOME}/.local/bin"
              "\${HOME}/.config/rofi/scripts"
            ];
          };
        };

        networking = {
          hostName = "home-kvm-hypervisor-1";
          networkmanager.enable = lib.mkForce false;
          useDHCP = false;
        };

        programs = {
          zsh.enable = true;
        };

        time = {
          timeZone = "Europe/London";
        };

        users.users.ali = {
          isNormalUser = true;
          description = "Alison Jenkins";
          initialPassword = "initPw!";
          extraGroups = [ "docker" "libvirtd" "wheel" ];
          openssh.authorizedKeys.keys = [ outputs.lib.sshKeys.primary ];
        };

        security = {
          sudo = {
            wheelNeedsPassword = lib.mkForce false;
          };
        };

        system.stateVersion = "24.05";

        systemd = {

          network = {
            enable = true;

            netdevs = {
              "20-br0" = {
                netdevConfig = {
                  Kind = "bridge";
                  Name = "br0";
                };
              };
            };

            networks = {
              "30-enp16s0" = {
                matchConfig.Name = "enp16s0";
                networkConfig = {
                  Bridge = "br0";
                };
                linkConfig = {
                  RequiredForOnline = "enslaved";
                };
              };

              "40-br0" = {
                DHCP = "yes";
                matchConfig.Name = "br0";
                bridgeConfig = {};
                dhcpV4Config = { UseDNS = true; UseRoutes = true; };
                linkConfig = {
                  RequiredForOnline = "routable";
                };
              };
            };
          };
        };

        virtualisation = {
          libvirtd = {
            package = inputs.nixpkgs_old.legacyPackages.${pkgs.stdenv.hostPlatform.system}.libvirt;
            qemu = {
              package = lib.mkForce inputs.nixpkgs_old.legacyPackages.${pkgs.stdenv.hostPlatform.system}.qemu;
              runAsRoot = true;
              swtpm.enable = true;
            };
          };

          libvirt = {
            enable = true;
            package = inputs.nixpkgs_old.legacyPackages.${pkgs.stdenv.hostPlatform.system}.libvirt;

            connections = {
              "qemu:///system" = {
                domains = [
                  {
                    active = true;
                    definition = pkgs.writeText "download-server-1.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/domains/download-server-1.xml.nix") {inherit pkgs;});
                  }
                  {
                    active = true;
                    definition = pkgs.writeText "home-k8s-master-1.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/domains/home-k8s-master-1.xml.nix") {inherit pkgs;});
                  }
                  {
                    active = true;
                    definition = pkgs.writeText "home-storage-server-1.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/domains/home-storage-server-1.xml.nix") {inherit pkgs;});
                  }
                  {
                    # Disabled: not needed. active=false keeps the domain defined
                    # but stopped and prevents libvirt autostart, reclaiming its
                    # 4 GiB reservation for the other VMs (notably jellyfin on
                    # home-k8s-master-1). Re-enable by flipping back to true.
                    active = false;
                    definition = pkgs.writeText "home-vpn-gateway-1.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/domains/home-vpn-gateway-1.xml.nix") {inherit pkgs;});
                  }
                  # {
                  #   active = true;
                  #   definition = pkgs.writeText "Unraid.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/domains/Unraid.xml.nix") {inherit pkgs;});
                  # }
                ];

                networks = [
                  {
                    active = true;
                    definition = pkgs.writeText "kvm-networks.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/networks/default.xml.nix"));
                  }
                ];

                pools = [
                  {
                    definition = self + "/libvirtd/home-kvm-hypervisor-1/pools/default.xml";

                    # volumes = [
                    # ];
                  }
                ];
              };
            };
          };
        };
      })
    ];
  };
}
