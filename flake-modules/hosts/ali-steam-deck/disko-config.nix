{ ... }: {
  flake.nixosModules.ali-steam-deck-disko-config = { lib, ... }: {
    disko.devices = {
      disk.disk1 = {
        device = lib.mkDefault "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              name = "boot";
              size = "1M";
              type = "EF02";
            };
            esp = {
              name = "ESP";
              size = "4G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                settings = {
                  keyFile = "/tmp/secret.key";
                  allowDiscards = true;
                };
                # Match SSD physical sector size (4 KiB) so
                # cryptsetup doesn't process 8x more blocks per
                # 4 KiB I/O. ~5-15% throughput improvement on
                # NVMe. Must be set at format time. Lives at the
                # disko LUKS top level (not inside `settings`,
                # which is verbatim-forwarded to NixOS's
                # `boot.initrd.luks.devices.<name>`).
                extraFormatArgs = [
                  "--sector-size"
                  "4096"
                ];
                content = {
                  type = "lvm_pv";
                  vg = "pool";
                };
              };
            };
          };
        };
      };
      lvm_vg = {
        pool = {
          type = "lvm_vg";
          lvs = {
            # Dedicated swap LV (encrypted inside LUKS) so hibernation
            # works. 32 GiB = 2x RAM, plenty of headroom for the
            # hibernate image + active swap during big game loads.
            # resumeDevice=true makes disko emit boot.resumeDevice
            # pointing at this LV.
            swap = {
              size = "32G";
              content = {
                type = "swap";
                discardPolicy = "both";
                resumeDevice = true;
              };
            };
            # Single XFS volume holds everything (/persistence, /nix,
            # /home) so we don't pre-commit space to a fixed split —
            # XFS can grow but can't shrink, so any partition layout
            # decided up-front would lock us in. /nix and /home are
            # bind-mounted from subdirs of /persistence in the host
            # config; this LV claims the rest of the VG.
            data = {
              size = "100%FREE";
              content = {
                type = "filesystem";
                format = "xfs";
                mountpoint = "/persistence";
                # XFS tuned for game/asset streaming + Nix store
                # writes. Same recipe as ali-desktop's
                # /media/steam-games-1 (commit 5df113b8), with extra
                # log buffer count for concurrent write throughput
                # during multi-game shader compiles.
                mountOptions = [
                  "noatime"          # No access-time writes on every read
                  "largeio"          # Hint kernel for large sequential I/O (asset streaming)
                  "allocsize=64m"    # Preallocate in 64 MiB chunks — less fragmentation on AAA installs
                  "logbsize=256k"    # Larger journal buffer for write throughput
                  "logbufs=8"        # Max in-memory log buffers — better concurrency on shader-cache writes
                  "inode64"          # Allow inodes anywhere in fs (default since 3.7, explicit for clarity)
                ];
              };
            };
          };
        };
      };
      nodev = {
        "/" = {
          fsType = "tmpfs";
          mountOptions = [
            "defaults"
            "mode=755"
            "size=8G"
          ];
        };
      };
    };

    fileSystems."/persistence".neededForBoot = true;
    fileSystems."/nix".neededForBoot = true;
  };
}
