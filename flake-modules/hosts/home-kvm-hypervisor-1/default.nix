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

        # Cap nix build parallelism well below the 64 hardware threads: base
        # sets max-jobs=auto / cores=0, which lets a rebuild schedule up to
        # 64 concurrent builds each with unbounded make -j, starving the
        # running VMs' vCPU threads. 4 jobs x 8 cores ~= half the machine.
        nix.settings = {
          max-jobs = lib.mkForce 4;
          cores = lib.mkForce 8;
        };
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
            # SAS3008 controllers (1000:0097) bound early via vfio-pci — prevents mpt3sas from claiming them.
            # Console/LUKS prompt renders via the ROMED8-2T's ASPEED BMC (ast/simpledrm); no discrete GPU fitted.
            "vfio-pci.ids=1000:0097"
            # Identity-map DMA for host-owned devices (X550 ixgbe, OS NVMe):
            # with the IOMMU enabled for VFIO, host devices otherwise pay full
            # DMA remapping on every transfer. Passthrough domains keep their
            # own translation — does not affect the HBA passthrough.
            "iommu=pt"
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

        # Cap zram at 50% of RAM (base sets 100%). zram is RAM-backed, so on a
        # host this tight an oversized zram could itself consume the RAM it is
        # meant to relieve. With swappiness raised, more lands in zram — this is
        # the guardrail. Only ~8.5 GiB is swappable here (22 GiB pinned), so
        # 50% is a safe ceiling, not a throughput limit.
        zramSwap.memoryPercent = lib.mkForce 50;

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

              # Isolated, host-only L2 bridge carrying the jumbo (MTU 9000)
              # storage network between download-server-1 and home-storage-server-1.
              # No physical uplink and no host IP — pure guest<->guest fast path so
              # the NFS data traffic stays off br0 (which must remain MTU 1500 for
              # the LAN). Guests attach a second virtio NIC to this bridge.
              "21-br-storage" = {
                netdevConfig = {
                  Kind = "bridge";
                  Name = "br-storage";
                };
              };
            };

            networks = {
              # Match the LAN uplink by driver, not interface name, so this
              # survived the EPYC/ROMED8-2T board swap. ixgbe now matches FOUR
              # ports (2x onboard X550 + 2x discrete X520 destined for the
              # firewall VM); only the cabled LAN port gets carrier and
              # actually joins br0. RequiredForOnline must be "no": a
              # carrier-less matched port never reaches "enslaved", so
              # "enslaved" here makes wait-online block on the three uncabled
              # ports. Host readiness is gated by "40-br0" routable instead.
              # TODO(firewall VM): replace the driver match with
              # matchConfig.PermanentMACAddress of the LAN port so the
              # WAN/passthrough ports never enslave to br0 (L2-loop guard —
              # br0 runs no STP).
              "30-lan-uplink" = {
                matchConfig.Driver = "ixgbe";
                networkConfig = {
                  Bridge = "br0";
                };
                linkConfig = {
                  RequiredForOnline = "no";
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

              # br-storage carries no host IP; force MTU 9000 and let it come up
              # without a carrier (members appear only when guests boot). Not
              # required for boot-online so a guest-down state never blocks the host.
              "41-br-storage" = {
                matchConfig.Name = "br-storage";
                networkConfig = {
                  ConfigureWithoutCarrier = true;
                  LinkLocalAddressing = "no";
                };
                linkConfig = {
                  MTUBytes = "9000";
                  RequiredForOnline = "no";
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
                    # Re-enabled after the EPYC/ROMED8-2T board swap. The GPU
                    # (1002:164e) was the previous CPU's iGPU and no longer exists on
                    # EPYC, so the GPU <hostdev> is commented out in the domain XML and
                    # this runs headless (Jellyfin software transcode) until a discrete
                    # GPU is fitted.
                    active = true;
                    definition = pkgs.writeText "home-k8s-master-1.xml" (import (self + "/libvirtd/home-kvm-hypervisor-1/domains/home-k8s-master-1.xml.nix") {inherit pkgs;});
                  }
                  {
                    # Re-enabled after the board swap. Passes through the SAS3008 HBA
                    # (1000:0097); on the new board the one dual-controller card sits at
                    # host 84:00.0 + 86:00.0 (both are in the domain XML). vfio-pci binds
                    # them via vfio-pci.ids so the address is fixed at boot.
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
