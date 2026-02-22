{ config, lib, pkgs, ... }:
let
  cfg = config.modules.rocm;
in
{
  options.modules.rocm = {
    enable = lib.mkEnableOption "ROCm GPU computing support";
  };

  config = lib.mkIf cfg.enable {
    environment = {
      systemPackages = with pkgs; [
        clinfo
        rocmPackages.rocminfo
      ];
    };

    hardware = {
      amdgpu = {
        initrd = {
          enable = true;
        };

        opencl = {
          enable = true;
        };
      };

      graphics = {
        extraPackages = with pkgs; [ rocmPackages.clr.icd ];
      };
    };
  };
}
