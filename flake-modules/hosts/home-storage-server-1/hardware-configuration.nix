{ ... }: {
  flake.nixosModules.home-storage-server-1-hardware = { config, lib, modulesPath, ... }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
    ];

    # VM variant configuration is now handled by the base module
    # See modules/base/vm-variant.nix
    vmVariantSettings = {
      memorySize = 4096;
      cores = 4;
      diskSize = 32768; # 32GB
      # Simplify filesystems - this storage server has complex mergerfs setup
      simplifyFilesystems = true;
    };

    boot = {
      kernelModules = [ "kvm-amd" ];
      extraModulePackages = [ ];

      initrd = {
        availableKernelModules = [
          "ahci"
          "cryptd"
          "ehci_pci"
          "nvme"
          "sd_mod"
          "sr_mod"
          "uas"
          "usb_storage"
          "usbhid"
          "virtio_blk"
          "virtio_pci"
          "xhci_pci"
        ];
        kernelModules = [ "dm-snapshot" "mpt3sas" ];
      };
    };

    fileSystems = let
      media_disks = {
        "/media/disks/ata-Hitachi_HDS5C3020ALA632_ML0220F31JAXAN-part1".device = "/dev/disk/by-id/ata-Hitachi_HDS5C3020ALA632_ML0220F31JAXAN-part1";
        "/media/disks/ata-Hitachi_HDS5C3020ALA632_ML2220F31WJ4LH-part1".device = "/dev/disk/by-id/ata-Hitachi_HDS5C3020ALA632_ML2220F31WJ4LH-part1";
        "/media/disks/ata-Hitachi_HDS722020ALA330_JK1174YAJ7MEVW-part1".device = "/dev/disk/by-id/ata-Hitachi_HDS722020ALA330_JK1174YAJ7MEVW-part1";
        "/media/disks/ata-SAMSUNG_HN-M101MBB_S2RXJ9AB908545-part1".device = "/dev/disk/by-id/ata-SAMSUNG_HN-M101MBB_S2RXJ9AB908545-part1";
        "/media/disks/ata-ST3000DM008-2DM166_Z5057TK6-part1".device = "/dev/disk/by-id/ata-ST3000DM008-2DM166_Z5057TK6-part1";
        "/media/disks/ata-ST3000DM008-2DM166_Z5057WSB-part1".device = "/dev/disk/by-id/ata-ST3000DM008-2DM166_Z5057WSB-part1";
        # "/media/disks/ata-ST4000DM004-2CV104_ZFN195XV-part1".device = "/dev/disk/by-id/ata-ST4000DM004-2CV104_ZFN195XV-part1"; # FAILING - blkid unreadable while running, did not reappear on reboot 2026-06-06 (wedged boot at tmpfiles). Pulled from pool pending replacement.
        # "/media/disks/ata-ST5000LM000-2AN170_WCJ53A54-part1".device = "/dev/disk/by-id/ata-ST5000LM000-2AN170_WCJ53A54-part1"; # Missing - not passed through to VM
        # "/media/disks/ata-ST5000LM000-2AN170_WCJ7DQKA-part1".device = "/dev/disk/by-id/ata-ST5000LM000-2AN170_WCJ7DQKA-part1"; # DEAD - I/O errors, bay 7
        "/media/disks/ata-TOSHIBA_MG08ACA16TE_71W0A3GYFWTG-part1".device = "/dev/disk/by-id/ata-TOSHIBA_MG08ACA16TE_71W0A3GYFWTG-part1";
        "/media/disks/ata-TOSHIBA_MG08ACA16TE_7190A01VFVGG-part1" = {
          device = "/dev/disk/by-id/ata-TOSHIBA_MG08ACA16TE_7190A01VFVGG-part1";
          fsType = "btrfs";
          options = [ "compress=zstd:-1" ];
        };
        "/media/disks/ata-TOSHIBA_MN10ADA10TS_Z5S2A05QFNGL-part1" = {
          device = "/dev/disk/by-id/ata-TOSHIBA_MN10ADA10TS_Z5S2A05QFNGL-part1";
          fsType = "btrfs";
          options = [ "compress=zstd:-1" ];
        };
        "/media/disks/ata-WDC_WD20SPZX-00UA7T0_WD-WX32A123N2JH-part1".device = "/dev/disk/by-id/ata-WDC_WD20SPZX-00UA7T0_WD-WX32A123N2JH-part1";
        "/media/disks/ata-WDC_WD20SPZX-22UA7T0_WD-WX72AA1HJFH3-part1".device = "/dev/disk/by-id/ata-WDC_WD20SPZX-22UA7T0_WD-WX72AA1HJFH3-part1";
        "/media/parity/ata-TOSHIBA_MG08ACA16TE_7190A0UNFVGG-part1".device = "/dev/disk/by-id/ata-TOSHIBA_MG08ACA16TE_7190A0UNFVGG-part1";
        "/media/disks/ata-ST31500341AS_9VS21EM9-part1".device = "/dev/disk/by-id/ata-ST31500341AS_9VS21EM9-part1";
        "/media/disks/ata-ST31500341AS_9VS21ESL-part1".device = "/dev/disk/by-id/ata-ST31500341AS_9VS21ESL-part1";
        "/media/disks/ata-ST31500341AS_9VS21WFH-part1" = {
          device = "/dev/disk/by-id/ata-ST31500341AS_9VS21WFH-part1";
          fsType = "ext4";  # the one non-xfs data disk
        };
        "/media/disks/ata-ST31500341AS_9VS21WMQ-part1".device = "/dev/disk/by-id/ata-ST31500341AS_9VS21WMQ-part1";
        # "/media/disks/ata-WDC_WD20EARX-00PASB0_WD-WCAZA9443921-part1".device = "/dev/disk/by-id/ata-WDC_WD20EARX-00PASB0_WD-WCAZA9443921-part1"; # DEAD - 996 pending sectors, physically removed
        "/media/disks/ata-WDC_WD20EARX-00PASB0_WD-WCAZAC311606-part1".device = "/dev/disk/by-id/ata-WDC_WD20EARX-00PASB0_WD-WCAZAC311606-part1"; # Marginal - 26 pending, monitor closely
      };
      # Default data disks to xfs (the common case here; btrfs/ext4 entries set
      # their own fsType above) and append nofail so a dead/missing drive doesn't
      # block boot — without preserving the entry's own fsType/options the
      # fileSystems eval fails with "fsType has no value".
      media_disks_nofail = builtins.mapAttrs
        (_: v: { fsType = "xfs"; } // v // { options = (v.options or [ ]) ++ [ "nofail" ]; })
        media_disks;
    in {
      "/".neededForBoot = true;
      "/nix".neededForBoot = true;
      "/persistence".neededForBoot = true;

      # NFS mount for BTFS streaming content from download-server-1
      "/media/btfs-streaming" = {
        device = "download-server-1.lan:/media/btfs-streaming";
        fsType = "nfs";
        options = [
          "ro"
          "soft"        # Fail quickly instead of hanging indefinitely when server is down
          "timeo=30"    # 3 second timeout (units of 0.1s)
          "retrans=2"   # 2 retries before failing
          "intr"
          "tcp"
          "nfsvers=4.2"
          "noac"        # Disable attribute caching - BTFS files grow in real-time
          "noauto"      # Don't mount at boot - use automount
          "x-systemd.automount"
          "x-systemd.idle-timeout=0"
        ];
      };

      "/media/storage" = {
        # Local disks only. The btfs-streaming NFS branch (from download-server-1)
        # was removed: its btfs-bridge service is dead and the NFS mount hung,
        # which wedged the pool and stalled boot at systemd-tmpfiles-setup. With
        # no network branch the pool mounts cleanly in local-fs (no _netdev).
        device = "/media/disks/*";
        fsType = "fuse.mergerfs";

        options = [
          "nofail"
          "allow_other"
          "cache.files=off"
          "category.create=mfs"  # Use most-free-space policy to spread data across disks
          "defaults"
          "dropcacheonclose=true"
          "fsname=mergerf"
          "minfreespace=200G"
          "moveonenospc=true"
          "nonempty"
          # NFS/SMB export safety: the pool is exported over NFS (download-server-1)
          # and SMB (home-cluster jellyfin). Those protocols are stateful and
          # inode-sensitive, so the pool needs stable, unique inodes across
          # branches. use_ino (per-branch inodes) caused empty/alternating
          # directory listings and "missing" files on clients. path-hash keeps
          # inodes stable even when files live on different disks; noforget stops
          # FUSE forgetting nodes (which NFS sees as ESTALE).
          "inodecalc=path-hash"
          "noforget"
          "security_capability=false"
          # Metadata/scan performance for NFS + SMB clients:
          # - cache.readdir: cache directory listings in the kernel
          # - nfsopenhack: work around NFS O_RDONLY-create POSIX incompatibility
          #
          # WARNING: these server-side options (and inodecalc=path-hash +
          # noforget above) do NOT make CLIENT-side NFS dentry caching safe.
          # The mergerfs+knfsd readdir paging bug means NFS clients must still
          # mount with lookupcache=none, or directory listings intermittently
          # truncate and clients (Sonarr/Radarr) think files are missing. Do not
          # "optimise" the client to lookupcache=pos/all again — that regression
          # (commit d790c5f3) caused ~460 redundant re-downloads in 2026-06.
          # See download-server-1/default.nix systemd.mounts for the full story.
          # NOTE: readdirplus is NOT a valid mount-time option in mergerfs 2.41.1
          # ("fuse: ERROR - unknown option - readdirplus=true" -> mount fails);
          # it's a runtime control only, so it is intentionally omitted here.
          "cache.readdir=true"
          "nfsopenhack=all"
        ];
      };
    } // media_disks_nofail;

    swapDevices = [
      {
        device = "/dev/pool/swap";
      }
    ];

    # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
    # (the default) this is the recommended approach. When using systemd-networkd it's
    # still possible to use this option, but it's recommended to use it in conjunction
    # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
    networking.useDHCP = lib.mkDefault true;
    # networking.interfaces.enp16s0.useDHCP = lib.mkDefault true;

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
