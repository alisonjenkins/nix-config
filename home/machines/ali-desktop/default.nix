{ pkgs, inputs, ... }: {
  imports = [
    ./easyeffects
    ../../programs/linux-only/sunshine-wrappers
    ../../programs/linux-only/steam-stream-mode
    # Disabled location-based audio settings (desktop doesn't move)
    # ./location-detection
    # ./audio-context
  ];

  modules.vr.enableOpenSourceVR = true;

  # Remote Play captures a whole output, so a Steam Deck otherwise receives
  # the 5120x1440 ultrawide letterboxed into 1280x360 of its 800-line panel,
  # showing whatever is on screen rather than the game. niri's dynamic cast
  # target follows a single window instead, which fixes both: the stream is
  # the game window, at the game window's size.
  custom.steamStreamMode = {
    enable = false;
    output = "DP-2";
    niriPackage = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri;
  };

  home.packages = [
    pkgs.nbt-studio
  ];

  # steam-command-runner intercepts `gamescope` in the Steam launch chain to
  # apply per-game gamescope arguments while keeping the Steam overlay and
  # stop button working. It only works under the name `gamescope` from
  # ~/.local/bin, which precedes the system profile in PATH; installing it
  # via home.packages would expose it under its own name and never be
  # reached. Previously a symlink to a debug build inside a working tree, so
  # every game's launch chain depended on an unpinned binary.
  home.file.".local/bin/gamescope".source =
    "${inputs.steam-command-runner.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/steam-command-runner";
}
