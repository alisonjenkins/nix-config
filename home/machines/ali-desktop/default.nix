{ pkgs, inputs, ... }: {
  imports = [
    ./easyeffects
    # Disabled location-based audio settings (desktop doesn't move)
    # ./location-detection
    # ./audio-context
  ];

  modules.vr.enableOpenSourceVR = true;

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
