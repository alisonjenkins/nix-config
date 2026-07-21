{ config, lib, ... }:
let
  cfg = config.modules.vfioIsolate;
in
{
  options.modules.vfioIsolate = {
    enable = lib.mkEnableOption "bind PCI devices to vfio-pci at boot for guest passthrough";

    pciIds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "1000:0097"
        "10de:1b81"
        "10de:10f0"
      ];
      description = ''
        `vendor:device` IDs (lowercase hex, as printed by `lspci -nn`) to claim
        with vfio-pci early at boot so the host's native driver never binds them
        and they are available for `<hostdev>` passthrough to a guest.

        All IDs are emitted as a SINGLE `vfio-pci.ids=` kernel parameter — the
        kernel only honours the last such parameter on the cmdline, so every
        passthrough device on this host must be listed here, not spread across
        multiple `boot.kernelParams` entries.

        A GPU is two functions (VGA + its HDMI-audio device); list both IDs.
        Binding an ID for a device that is not physically present is harmless
        (vfio-pci simply matches nothing), so IDs may be added before the card
        is seated.
      '';
    };

    blacklistDrivers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "nouveau" ];
      description = ''
        Host kernel modules to blacklist so they cannot race vfio-pci for a
        passthrough device (e.g. `nouveau` for an NVIDIA card). vfio-pci.ids
        already claims the device first, but blacklisting the native driver is
        belt-and-suspenders against probe ordering.
      '';
    };

    amdIommu = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Append `amd_iommu=on` to the kernel cmdline. Required for VFIO on AMD
        (EPYC/Ryzen) hosts. Independent of `iommu=pt`, which the host may set
        separately for DMA passthrough of host-owned devices.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.pciIds != [ ];
        message = "modules.vfioIsolate.enable is true but pciIds is empty — nothing to bind.";
      }
    ];

    boot = {
      kernelParams = [
        "vfio-pci.ids=${lib.concatStringsSep "," cfg.pciIds}"
      ]
      ++ lib.optional cfg.amdIommu "amd_iommu=on";

      blacklistedKernelModules = cfg.blacklistDrivers;

      # Load the vfio stack in the initrd so it claims the listed devices before
      # any native driver (nouveau/amdgpu/mpt3sas) probes them. Ordering only
      # matters for devices with an in-tree host driver; harmless otherwise.
      initrd.kernelModules = [
        "vfio_pci"
        "vfio"
        "vfio_iommu_type1"
      ];
    };
  };
}
