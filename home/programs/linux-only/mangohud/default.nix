{ lib, config, pkgs, ... }:

let
  cfg = config.custom.mangohud;
  # Cap slightly below the panel's max so VRR stays engaged: at or above max
  # refresh the frame limiter bounces off the vsync ceiling and VRR disengages.
  fpsCap = cfg.displayMaxRefresh - 4;

  layerDir = "${pkgs.mangohud}/share/vulkan/implicit_layer.d";
  mangohudLayer = name: manifest: {
    control = "auto";
    inherit name;
    path = "${layerDir}/${manifest}";
    treat_as_implicit_manifest = true;
  };
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

    firstVulkanLayer = lib.mkEnableOption ''
      placing MangoHud first in every Vulkan layer chain, nearest the
      application, through a Vulkan loader settings file. Steam Remote Play's
      game capture grabs frames in the Steam overlay layer, which otherwise
      sits before MangoHud, so the HUD was drawn after capture and missing
      from the stream. See docs/adr/0011-mangohud-first-vulkan-layer.md'';
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.firstVulkanLayer {
      xdg.configFile."vulkan/loader_settings.d/vk_loader_settings.json".text =
        builtins.toJSON {
          file_format_version = "1.0.0";
          settings.layers = [
            (mangohudLayer "VK_LAYER_MANGOHUD_overlay_64_x86_64" "MangoHud.x86_64.json")
            (mangohudLayer "VK_LAYER_MANGOHUD_overlay_32_x86" "MangoHud.x86.json")
            { control = "unordered_layer_location"; }
          ];
        };
    })
    {
      home.file.".config/MangoHud/MangoHud.conf".text =
        builtins.readFile ./MangoHud.conf
        + (if cfg.displayMaxRefresh != null then ''
          fps_limit=${toString fpsCap},0
        '' else ''
          fps_limit=0
        '');
    }
  ];
}
