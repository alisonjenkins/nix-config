{ pkgs, inputs, ... }: {
  imports = [
    ./easyeffects
    ../../programs/linux-only/steam-command-runner
    ../../programs/linux-only/sunshine-wrappers
    ../../programs/linux-only/steam-stream-mode
    # Disabled location-based audio settings (desktop doesn't move)
    # ./location-detection
    # ./audio-context
  ];

  modules.vr.enableOpenSourceVR = true;

  # Remote Play captures the whole DP-2 output, so a Steam Deck otherwise
  # receives the 5120x1440 ultrawide letterboxed into 1280x360 of its 800-line
  # panel. The mode is matched to the client when it connects — before Steam
  # negotiates capture, since the PipeWire stream does not follow a later
  # change — and restored once streaming has been idle.
  # Disabled pending a rework: switching the mode mid-session does not work,
  # and the capture follows the output rather than the game window.
  custom.steamStreamMode = {
    enable = false;
    output = "DP-2";
    niriPackage = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri;
  };

  home.packages = [
    pkgs.nbt-studio
  ];

  # obs-gamecapture LD_PRELOADs obs-vkcapture's Vulkan/GL hook so OBS's Game
  # Capture source can find any game launched through steam-command-runner,
  # without adding it per-game as a Steam launch option.
  programs.steamCommandRunner = {
    enable = true;
    preCommand = "obs-gamecapture gamemoderun";
    defaultProton = "DW-Proton Latest";
    shimDebug = true;
    innerEnv.MANGOHUD = "1";
    gamescopeArgs = "-w 2540 -h 1440 -W 2540 -H 1440 -b --rt --hdr-enabled --hdr-debug-force-support --force-grab-cursor -F fsr -r 120";
    # Almost every launch here goes through gamescope, so the module default
    # of skipping preCommand under gamescope would silently drop the
    # obs-gamecapture wrap for nearly all games.
    gamescopeSkipPreCommand = false;
  };

  # The module above writes the runner's config; this puts the runner itself
  # where Steam's launch chain will find it. It intercepts `gamescope` to
  # apply per-game arguments while keeping the Steam overlay and stop button
  # working, and only does so under the name `gamescope` from ~/.local/bin,
  # which precedes the system profile in PATH — installing it via
  # home.packages would expose it under its own name and never be reached.
  # Previously a symlink to a debug build inside a working tree, so every
  # game's launch chain depended on an unpinned binary.
  home.file.".local/bin/gamescope".source =
    "${inputs.steam-command-runner.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/steam-command-runner";
}
