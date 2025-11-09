{
  # VM-specific disko configuration - simplified without encryption/swap
  # This maintains impermanence (tmpfs root) while avoiding the complexity
  # of LUKS encryption and LVM that can cause hangs in VM environments
  disko.devices = {
    disk = {
      vda = {
        type = "disk";
        device = "/dev/vda";
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
                mountOptions = [ "defaults" ];
              };
            };
            nix = {
              size = "12G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/nix";
                mountOptions = [ "noatime" ];
              };
            };
            persistence = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/persistence";
                mountOptions = [ "noatime" ];
              };
            };
          };
        };
      };
    };
    nodev = {
      "/" = {
        fsType = "tmpfs";
        mountOptions = [ "defaults" "mode=755" "size=4G" ];
      };
    };
  };
}