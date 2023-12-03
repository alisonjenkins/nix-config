{ lib, disks ? [ "/dev/vda" ], ... }: {
  disko.devices = {
      disk = lib.genAttrs [ "1" "2" ] (id: {
        type = "disk";
        device = "/dev/nvme${id}n1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02"; # for grub MBR
              label = "${id}-grub";
            };
            ESP = {
              size = "4000M";
              type = "EF00";
              label = "${id}-esp";
              content = {
                type = "mdraid";
                name = "boot";
              };
            };
            mdadm = {
              size = "100%";
              label = "${id}-os_raid1";
              content = {
                type = "mdraid";
                name = "os_raid1";
              };
            };
          };
        };
      }
    );
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
              resumeDevice = true;
            };
          };
          root = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
