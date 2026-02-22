{ config, lib, ... }:
let
  cfg = config.modules.vr;
in
{
  options.modules.vr = {
    enable = lib.mkEnableOption "VR support";
    enableOpenSourceVR = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable open source VR stack (Envision + WiVRn)";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [ { } (lib.mkIf cfg.enableOpenSourceVR {
    programs = {
      envision = {
        enable = true;
        openFirewall = true;
      };
    };

    services = {
      wivrn = {
        enable = true;
        openFirewall = true;
        defaultRuntime = true;
        autoStart = true;
        config = {
          enable = true;

          json = {
            # 1.0x foveation scaling
            scale = 1.0;
            # 100 Mb/s
            bitrate = 100000000;
            encoders = [
              {
                encoder = "vaapi";
                codec = "h265";
                # 1.0 x 1.0 scaling
                width = 1.0;
                height = 1.0;
                offset_x = 0.0;
                offset_y = 0.0;
              }
            ];
          };
        };
      };
    };
  }) ]);
}
