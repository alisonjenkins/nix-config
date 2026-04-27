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
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" "-L" "crypted" ];
                  subvolumes = {
                    "@nix" = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "compress=zstd:-1"
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                        "discard=async"
                      ];
                    };
                    "@persistence" = {
                      mountpoint = "/persistence";
                      mountOptions = [
                        "compress=zstd:-1"
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                        "discard=async"
                      ];
                    };
                    "@home" = {
                      mountpoint = "/home";
                      mountOptions = [
                        "compress=zstd:-1"
                        "noatime"
                        "ssd"
                        "space_cache=v2"
                        "discard=async"
                      ];
                    };
                    "@swap" = {
                      mountpoint = "/swap";
                      swap.swapfile.size = "16G";
                    };
                  };
                };
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
