{ pkgs, inputs, ... }:
let
  # 1440 high with a borderless window. These launched with `LD_PRELOAD=""`
  # to keep Steam's preloads off gamescope; the runner no longer needs that.
  borderless1440Game = {
    gamescope_args = "-w 2560 -h 1440 -b";
  };

  # VR games: pressure-vessel has to see the host's OpenXR runtime (SteamVR),
  # and they never ran under gamescope, so skip the global gamescope arguments.
  vrGame = {
    env.PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
    gamescope_enabled = false;
  };
in
{
  imports = [
    ./easyeffects
    ./location-detection
    ./audio-context
    ../../programs/linux-only/steam-command-runner
  ];

  # amdgpu_bl2 is the only backlight; pinned so the brightness keys and bar
  # widget address the panel instead of guessing a backend.
  custom.noctalia.settings = {
    brightness.monitor."eDP-2" = {
      backend = "backlight";
      backlight_device = "amdgpu_bl2";
    };

    # Login box placed in the Settings menu for the 1707x1067 logical eDP-2.
    lockscreen_widgets = {
      enabled = false;
      schema_version = 2;
      widget_order = [ "lockscreen-login-box@eDP-2" ];
      grid = {
        cell_size = 16;
        major_interval = 4;
        visible = true;
      };
      widget."lockscreen-login-box@eDP-2" = {
        type = "login_box";
        output = "eDP-2";
        box_height = 196.0;
        box_width = 720.0;
        cx = 854.0;
        cy = 948.0;
        placement_height = 1067.0;
        placement_width = 1707.0;
        rotation = 0.0;
        settings = {
          background_color = "surface_container";
          background_opacity = 0.88;
          background_radius = 12.0;
          center_password_text = false;
          input_opacity = 1.0;
          input_radius = 6.0;
          layout = "regular";
          show_caps_lock = true;
          show_keyboard_layout = true;
          show_login_button = true;
          show_media = true;
          show_session_buttons = true;
          show_unlock_hint = true;
          show_weather = true;
        };
      };
    };
  };

  modules.beatsaber.enable = true;
  modules.helldivers2Mods.enable = true;

  # Carries what the games' Steam launch options used to say
  # (docs/steam-launch-options-2026-10-30.md): most ran
  # `gamemoderun mangohud gamescope -w 2560 -h 1600`.
  programs.steamCommandRunner = {
    enable = true;
    preCommand = "gamemoderun";
    # Under gamescope too, as those launches had gamemoderun in them.
    gamescopeSkipPreCommand = false;
    shimDebug = true;
    env.LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib:/run/current-system/sw/lib";
    innerEnv.MANGOHUD = "1";
    gamescopeArgs = "-w 2560 -h 1600";

    games."582160" = borderless1440Game; # Assassin's Creed Origins
    games."812140" = borderless1440Game; # Assassin's Creed Odyssey
    games."2464530" = borderless1440Game; # VOIN
    games."3035570" = borderless1440Game; # Assassin's Creed Mirage

    games."438100" = vrGame; # VRChat
    games."457960" = vrGame; # Holopoint
    games."620980" = vrGame; # Beat Saber
    games."826540" = vrGame; # Audio Trip
    games."1079800" = vrGame; # Pistol Whip
    games."2465270" = vrGame; # name not in the store API

    # Risk of Rain 2: was launched without gamescope, and with the lavapipe
    # software Vulkan ICD disabled.
    games."632360" = {
      gamescope_enabled = false;
      env.VK_LOADER_DRIVERS_DISABLE = "lvp_icd";
    };

    # Launched without gamescope (FF7 Remake with only `gamemoderun`, Golf
    # with no options), so the global gamescope arguments stay off them.
    games."431240".gamescope_enabled = false; # Golf With Your Friends
    games."1462040".gamescope_enabled = false; # FF7 Remake Intergrade
  };

  home.packages = [
    pkgs.nbt-studio
  ];

  # Games carry `~/.local/bin/gamescope -- %command%` launch options (Steam
  # cloud sync). The runner only intercepts under the name `gamescope`, and
  # ~/.local/bin precedes the system profile in PATH.
  home.file.".local/bin/gamescope".source =
    "${inputs.steam-command-runner.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/steam-command-runner";
}
