{
  disko.devices = {
    nodev = {
      "/" = {
        fsType = "tmpfs";
        mountOptions = [
          "defaults"
          "size=16G"
          "mode=755"
        ];
      };
    };

    disk = {
      boot = {
        device = "/dev/disk/by-uuid/12AE-8C8B";
        type = "disk";
        content = {
          type = "filesystem";
          format = "vfat";
          mountpoint = "/boot";
        };
      };

      luksroot = {
        type = "disk";
        device = "/dev/disk/by-uuid/251edf6c-ec46-4734-97ad-1caab10a6246";
        size = "100%";
        content = {
          type = "luks";
          name = "luksroot";
          extraOpenArgs = [];
          settings = {
            keyFile = "/tmp/secret.key";
            allowDiscards = true;
          };
          content = {
            type = "lvm_pv";
            vg = "osvg";
          };
        };
      };
    };

    lvm_vg = {
      osvg = {
        type = "lvm_vg";
        lvs = {
          root = {
            size = "75.43GiB";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/media/archroot";
              mountOptions = [
                "defaults"
                "noatime"
                "discard"
              ];
            };
          };

          steam-games-1 = {
            size = "1.68TiB";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/media/steam-games-1";
              mountOptions = [
                "defaults"
                "noatime"
                "barrier=0"
                "data=writeback"
                "discard"
              ];
            };
          };

          persistence = {
            size = "510.50GiB";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];
              subvolumes = {
                "nix" = {
                  mountpoint = "/nix";
                  mountOptions = ["compress=zstd" "noatime"];
                };

                "persistence" = {
                  mountpoint = "/persistence";
                  mountOptions = ["compress=zstd" "noatime"];
                };
              };
            };
          };

          linuxswap = {
            size = "64GiB";
            content = {
              type = "swap";
              discardPolicy = "both";
              resumeDevice = true;
            };
          };
        };
      };
    };

    # disk = {
    #   disk0 = {
    #     type = "disk";
    #     device = "/dev/disk/by-id/ata-QEMU_HARDDISK_QM00001";
    #     content = {
    #       type = "gpt";
    #       partitions = {
    #         ESP = {
    #           start = "1M";
    #           end = "128M";
    #           type = "EF00";
    #           content = {
    #             type = "filesystem";
    #             format = "vfat";
    #             mountpoint = "/boot";
    #           };
    #         };
    #       };
    #     };
    #   };
    #   disk1 = {
    #     type = "disk";
    #     device = "/dev/disk/by-id/ata-QEMU_HARDDISK_QM00002";
    #     content = {
    #       type = "gpt";
    #       partitions = {
    #         luks = {
    #           start = "1M";
    #           size = "100%";
    #           content = {
    #             type = "luks";
    #             name = "crypted1";
    #             settings.keyFile = "/tmp/secret.key";
    #             additionalKeyFiles = [ "/tmp/additionalSecret.key" ];
    #             extraFormatArgs = [
    #               "--iter-time 1" # insecure but fast for tests
    #             ];
    #             content = {
    #               type = "lvm_pv";
    #               vg = "pool";
    #             };
    #           };
    #         };
    #       };
    #     };
    #   };
    #   disk2 = {
    #     type = "disk";
    #     device = "/dev/disk/by-id/ata-QEMU_HARDDISK_QM00003";
    #     content = {
    #       type = "gpt";
    #       partitions = {
    #         luks = {
    #           start = "1M";
    #           size = "100%";
    #           content = {
    #             type = "luks";
    #             name = "crypted2";
    #             settings = {
    #               keyFile = "/tmp/secret.key";
    #               keyFileSize = 8;
    #               keyFileOffset = 2;
    #             };
    #             extraFormatArgs = [
    #               "--iter-time 1" # insecure but fast for tests
    #             ];
    #             content = {
    #               type = "lvm_pv";
    #               vg = "pool";
    #             };
    #           };
    #         };
    #       };
    #     };
    #   };
    # };
    # mdadm = {
    #   raid1 = {
    #     type = "mdadm";
    #     level = 1;
    #     content = {
    #       type = "gpt";
    #       partitions = {
    #         bla = {
    #           start = "1M";
    #           size = "100%";
    #           content = {
    #             type = "filesystem";
    #             format = "ext4";
    #             mountpoint = "/ext4_mdadm_lvm";
    #           };
    #         };
    #       };
    #     };
    #   };
    # };
    # lvm_vg = {
    #   pool = {
    #     type = "lvm_vg";
    #     lvs = {
    #       root = {
    #         size = "10M";
    #         lvm_type = "mirror";
    #         content = {
    #           type = "filesystem";
    #           format = "ext4";
    #           mountpoint = "/ext4_on_lvm";
    #           mountOptions = [
    #             "defaults"
    #           ];
    #           postMountHook = ''
    #             touch /mnt/ext4_on_lvm/file-from-postMountHook
    #           '';
    #         };
    #       };
    #       raid1 = {
    #         size = "30M";
    #         lvm_type = "raid0";
    #         content = {
    #           type = "mdraid";
    #           name = "raid1";
    #         };
    #       };
    #       raid2 = {
    #         size = "30M";
    #         lvm_type = "raid0";
    #         content = {
    #           type = "mdraid";
    #           name = "raid1";
    #         };
    #       };
    #       zfs1 = {
    #         size = "128M";
    #         lvm_type = "raid0";
    #         content = {
    #           type = "zfs";
    #           pool = "zroot";
    #         };
    #       };
    #       zfs2 = {
    #         size = "128M";
    #         lvm_type = "raid0";
    #         content = {
    #           type = "zfs";
    #           pool = "zroot";
    #         };
    #       };
    #     };
    #   };
    # };
    # zpool = {
    #   zroot = {
    #     type = "zpool";
    #     mode = "mirror";
    #     rootFsOptions = {
    #       compression = "zstd";
    #       "com.sun:auto-snapshot" = "false";
    #     };
    #     mountpoint = "/";
    #
    #     datasets = {
    #       zfs_fs = {
    #         type = "zfs_fs";
    #         mountpoint = "/zfs_fs";
    #         options."com.sun:auto-snapshot" = "true";
    #       };
    #       zfs_unmounted_fs = {
    #         type = "zfs_fs";
    #         options.mountpoint = "none";
    #       };
    #       zfs_legacy_fs = {
    #         type = "zfs_fs";
    #         options.mountpoint = "legacy";
    #         mountpoint = "/zfs_legacy_fs";
    #       };
    #       zfs_testvolume = {
    #         type = "zfs_volume";
    #         size = "10M";
    #         content = {
    #           type = "filesystem";
    #           format = "ext4";
    #           mountpoint = "/ext4onzfs";
    #         };
    #       };
    #     };
    #   };
    # };
  };
}
