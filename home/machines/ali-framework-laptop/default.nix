{ pkgs, inputs, ... }: {
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
