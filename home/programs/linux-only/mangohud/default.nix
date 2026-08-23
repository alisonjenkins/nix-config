{ lib, config, ... }:

let
  cfg = config.custom.mangohud;
  # Cap slightly below the panel's max so VRR stays engaged: at or above max
  # refresh the frame limiter bounces off the vsync ceiling and VRR disengages.
  fpsCap = cfg.displayMaxRefresh - 4;
in
{
  options.custom.mangohud = {
    displayMaxRefresh = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      example = 120;
      description = ''
        Max refresh rate (Hz) of this machine's gaming display. When set,
        MangoHud caps games at 4 fps below it (VRR-friendly), with
        toggle_fps_limit (Shift_L+F1) switching back to uncapped.
        null leaves games uncapped.
      '';
    };
  };

  config = {
    home.file.".config/MangoHud/MangoHud.conf".text =
      builtins.readFile ./MangoHud.conf
      + (if cfg.displayMaxRefresh != null then ''
        fps_limit=${toString fpsCap},0
      '' else ''
        fps_limit=0
      '');
  };
}
