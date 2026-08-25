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

  # Remote Play captures a whole output and Steam only ever asks the portal
  # for monitors, so on the 5120x1440 ultrawide a Deck received about 1280x360
  # of content inside its 800-line frame, showing whatever was on screen. A
  # niri virtual output at the client's own resolution is created on connect
  # and the game is moved onto it, leaving DP-2 untouched.
  custom.steamStreamMode = {
    enable = true;
    # niriPackage is set from the host config, where the patched package the
    # session actually runs is in scope — `niri msg` has to match the running
    # compositor, and virtual output support is a patch rather than upstream.
    # The Steam Deck's panel; overridden per client once learned.
    defaultWidth = 1280;
    defaultHeight = 800;
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
