{ pkgs, inputs, ... }: {
  imports = [
    ./easyeffects
    ../../programs/linux-only/sunshine-wrappers
    ../../programs/linux-only/steam-stream-mode
    ../../programs/linux-only/steam-headless
    # Disabled location-based audio settings (desktop doesn't move)
    # ./location-detection
    # ./audio-context
  ];

  modules.vr.enableOpenSourceVR = true;

  # Remote Play captures the whole DP-2 output, so without this a Steam Deck
  # receives the 5120x1440 ultrawide letterboxed into 1280x360 of its 800-line
  # panel. Steam has no prep-command hook, so the switch is driven off its
  # streaming log instead, which also means it works when nobody is at the
  # machine to run a command.
  # Steam is single-instance, so the headless streaming session and the
  # desktop client cannot coexist. This flips between them: a stream starting
  # against the desktop session switches the machine to headless, and it
  # returns once streaming has been idle. Streaming wins, and the client pays
  # one reconnect for the flip.
  custom.steamStreamMode = {
    enable = true;
    output = "DP-2";
    niriPackage = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri;
  };

  # On-demand headless gamescope Steam session. gamescope --backend headless
  # presents no Wayland surface, so there is no desktop behind the game and
  # nothing for niri to tile — the game fills the client's frame by
  # construction, with no output mode change involved.
  #
  # Start with `systemctl --user start steam-headless`, which works over SSH.
  # It stops the desktop Steam client first, because Steam is single-instance.
  custom.steamHeadless = {
    enable = true;
    # The Steam Deck's panel. Revisit when the Frame's resolution is known.
    width = 1280;
    height = 800;
    refresh = 60;
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
