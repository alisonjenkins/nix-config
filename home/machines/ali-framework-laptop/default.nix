{ pkgs, inputs, ... }: {
  imports = [
    ./easyeffects
    ./location-detection
    ./audio-context
    ../../programs/linux-only/steam-command-runner
  ];

  modules.beatsaber.enable = true;
  modules.helldivers2Mods.enable = true;

  programs.steamCommandRunner = {
    enable = true;
    preCommand = "gamemoderun";
    shimDebug = true;
    env.LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib:/run/current-system/sw/lib";
    innerEnv.MANGOHUD = "1";
    gamescopeArgs = "-w 2560 -h 1600 --rt -b --mangoapp --force-grab-cursor";
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
