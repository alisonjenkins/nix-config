{ pkgs, inputs, ... }:
let
  # Launched as `LD_PRELOAD="" gamescope -w 2540 -h 1440 -b -- gamemoderun`:
  # no Steam preloads reach gamescope, 1440 high with a borderless window.
  noPreloadGame = {
    env.LD_PRELOAD = "";
    gamescope_args = "-w 2540 -h 1440 -b";
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

  modules.beatsaber.enable = true;
  modules.helldivers2Mods.enable = true;

  # Carries what the games' Steam launch options used to say
  # (docs/steam-launch-options-2026-10-30.md): most ran
  # `gamemoderun mangohud gamescope -w 2540 -h 1600`.
  programs.steamCommandRunner = {
    enable = true;
    preCommand = "gamemoderun";
    # Under gamescope too, as those launches had gamemoderun in them.
    gamescopeSkipPreCommand = false;
    shimDebug = true;
    env.LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib:/run/current-system/sw/lib";
    innerEnv.MANGOHUD = "1";
    gamescopeArgs = "-w 2540 -h 1600";

    games."582160" = noPreloadGame; # Assassin's Creed Origins
    games."812140" = noPreloadGame; # Assassin's Creed Odyssey
    games."2464530" = noPreloadGame; # VOIN
    games."3035570" = noPreloadGame; # Assassin's Creed Mirage

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
