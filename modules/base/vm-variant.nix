{ config
, lib
, modulesPath
, ...
}:
let
  cfg = config.vmVariantSettings;
in
{
  options.vmVariantSettings = {
    enable = lib.mkEnableOption "VM variant configuration" // {
      default = true;
    };

    memorySize = lib.mkOption {
      type = lib.types.int;
      default = 4096;
      description = "Memory size in MiB for the VM";
    };

    cores = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Number of CPU cores for the VM";
    };

    diskSize = lib.mkOption {
      type = lib.types.int;
      default = 32768;
      description = "Disk size in MiB for the VM";
    };

    graphics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable graphics for the VM";
    };

    disableLuks = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Disable LUKS encryption in VM variant";
    };

    disableSecureBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Disable secure boot (lanzaboote) in VM variant";
    };

    configureBootLoader = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Automatically configure boot loader for VM (set to false for custom boot loader config)";
    };

    simplifyFilesystems = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Simplify filesystem configuration for VM (disables complex mounts)";
    };
  };

  options.system.isVM = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether this system is running as a VM";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.vmVariant = {
      # Set the isVM flag
      system.isVM = true;

      # Core VM settings
      virtualisation = {
        memorySize = cfg.memorySize;
        cores = cfg.cores;
        diskSize = cfg.diskSize;
        graphics = cfg.graphics;

        # Share the Nix store from the host
        sharedDirectories = {
          nix-store = {
            source = "/nix/store";
            target = "/nix/.ro-store";
          };
        };
      };

      # Boot configuration
      boot = lib.mkMerge [
        {
          # Disable LUKS encryption if configured
          initrd.luks.devices = lib.mkIf cfg.disableLuks (lib.mkForce { });
        }
        (lib.mkIf cfg.disableSecureBoot {
          # Disable secure boot
          lanzaboote.enable = lib.mkForce false;
        })
        (lib.mkIf (cfg.configureBootLoader && cfg.disableSecureBoot) {
          # Enable systemd-boot - need to override any host settings
          loader.systemd-boot.enable = lib.mkOverride 10 true;
          loader.efi.canTouchEfiVariables = lib.mkOverride 10 true;
        })
      ];

      # Simplify filesystem configuration for VMs
      fileSystems = lib.mkIf cfg.simplifyFilesystems (lib.mkForce {
        "/" = {
          device = "/dev/vda";
          fsType = "ext4";
          autoFormat = true;
        };

        "/boot" = lib.mkIf config.boot.loader.systemd-boot.enable {
          device = "/dev/disk/by-label/ESP";
          fsType = "vfat";
        };
      });

      # Disable swap devices in VMs
      swapDevices = lib.mkIf cfg.simplifyFilesystems (lib.mkForce [ ]);

      # Simplify networking for VMs
      networking.useDHCP = lib.mkForce true;
    };
  };
}
