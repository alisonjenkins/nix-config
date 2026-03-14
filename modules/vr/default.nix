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

  config = lib.mkIf (cfg.enable && cfg.enableOpenSourceVR) {
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
            # Foveated rendering: render periphery at lower resolution to reduce
            # encoding load and bandwidth while keeping the center sharp
            scale = 0.8;
            # 50 Mb/s — H.265 is efficient enough; lower bitrate reduces Wi-Fi
            # congestion and improves frame consistency
            bitrate = 50000000;
            # Split frame into two slices encoded in parallel to halve encode latency
            encoders = [
              {
                encoder = "vaapi";
                codec = "h265";
                width = 1.0;
                height = 0.5;
                offset_x = 0.0;
                offset_y = 0.0;
              }
              {
                encoder = "vaapi";
                codec = "h265";
                width = 1.0;
                height = 0.5;
                offset_x = 0.0;
                offset_y = 0.5;
              }
            ];
          };
        };
      };
    };
  };
}
