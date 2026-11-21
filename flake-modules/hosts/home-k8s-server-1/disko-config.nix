{ ... }: {
  flake.nixosModules.home-k8s-server-1-disko-config = {
    disko.devices = {
      disk = {
        main = {
          type = "disk";
          # Kingston SA400 120G SATA SSD (the fitlet2's only disk).
          device = "/dev/disk/by-id/ata-KINGSTON_SA400M8120G_50026B7683D9077F";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "500M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [
                    "defaults"
                  ];
                };
              };
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypted";
                  extraOpenArgs = [ ];
                  passwordFile = "/tmp/secret.key";
                  settings.allowDiscards = true;
                  content = {
                    type = "lvm_pv";
                    vg = "pool";
                  };
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
