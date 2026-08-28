{ ... }: {
  flake.nixosModules.home-kvm-hypervisor-1-disko-config = { ... }: {
    disko.devices = {
      # Kernel NVMe enumeration (nvme0n1/nvme1n1/nvme2n1) is not stable across
      # this host's NVMe controllers/PCIe topology — it already drifted once
      # (observed after the EPYC board swap: both boot disks re-enumerated,
      # and a third, unrelated Samsung 960 PRO ended up occupying the
      # "nvme1n1" slot the old /dev/nvme${id}n1 template assumed was a boot
      # disk). disko derives `boot.loader.grub.devices` from these paths, so
      # a stale path here means grub-install silently targets the wrong
      # disk on the next deploy. by-id paths key off the drive's own
      # serial, so they survive any future re-enumeration. Mapping below
      # was cross-checked against the ALREADY-WRITTEN on-disk PARTLABELs
      # (`1-grub`/`1-esp`/`1-os_raid1` etc, via `lsblk -o PARTLABEL`) rather
      # than assumed from current device names — id "1" and "2" are kept
      # exactly as before so those labels stay correct without a relabel.
      disk = {
        "1" = {
          type = "disk";
          # Crucial CT1000P3PSSD8, serial 240746DD9716 (currently nvme2n1).
          device = "/dev/disk/by-id/nvme-CT1000P3PSSD8_240746DD9716";
          content = {
            type = "gpt";
            partitions = {
              boot = {
                size = "1M";
                type = "EF02"; # for grub MBR
                label = "1-grub";
              };
              ESP = {
                size = "4000M";
                type = "EF00";
                label = "1-esp";
                content = {
                  type = "mdraid";
                  name = "boot";
                };
              };
              mdadm = {
                size = "100%";
                label = "1-os_raid1";
                content = {
                  type = "mdraid";
                  name = "os_raid1";
                };
              };
            };
          };
        };
        "2" = {
          type = "disk";
          # Crucial CT1000P3PSSD8, serial 240746DDA3ED (currently nvme0n1).
          device = "/dev/disk/by-id/nvme-CT1000P3PSSD8_240746DDA3ED";
          content = {
            type = "gpt";
            partitions = {
              boot = {
                size = "1M";
                type = "EF02"; # for grub MBR
                label = "2-grub";
              };
              ESP = {
                size = "4000M";
                type = "EF00";
                label = "2-esp";
                content = {
                  type = "mdraid";
                  name = "boot";
                };
              };
              mdadm = {
                size = "100%";
                label = "2-os_raid1";
                content = {
                  type = "mdraid";
                  name = "os_raid1";
                };
              };
            };
          };
        };
      };
      mdadm = {
        boot = {
          type = "mdadm";
          level = 1;
          metadata = "1.0";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        os_raid1 = {
          type = "mdadm";
          level = 1;
          content = {
            type = "luks";
            name = "os_raid1_crypt";
            settings.allowDiscards = true;
            passwordFile = "/tmp/secret.key";
            # Match SSD physical sector size (4 KiB) for ~5-15%
            # NVMe throughput improvement. Format-time only;
            # applies on next reinstall.
            extraFormatArgs = [
              "--sector-size"
              "4096"
            ];
            content = {
              type = "lvm_pv";
              vg = "os_raid1";
            };
          };
        };
      };
      lvm_vg = {
        os_raid1 = {
          type = "lvm_vg";
          lvs = {
            swap = {
              size = "32G";
              content = {
                type = "swap";
                # Hibernation is unusable on this host: VFIO passthrough
                # domains pin their RAM and cannot be suspended to disk.
                # resumeDevice=true only injected pointless resume= boot logic.
                resumeDevice = false;
              };
            };
            root = {
              size = "100%FREE";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                mountOptions = [
                  "noatime"
                  "discard"
                ];
              };
            };
          };
        };
      };
    };
  };
}
