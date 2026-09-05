{ config, pkgs, inputs, ... }: {
  imports = [
    ./easyeffects
    ../../programs/linux-only/steam-command-runner
    ../../programs/linux-only/sunshine-wrappers
    ../../programs/linux-only/steam-stream-mode
    ../../programs/linux-only/uhk-keymaps
    # Disabled location-based audio settings (desktop doesn't move)
    # ./location-detection
    # ./audio-context
  ];

  modules.vr.enableOpenSourceVR = true;

  # Remote Play captures a whole output and Steam only ever asks the portal
  # for monitors, so on the 5120x1440 ultrawide a Deck received about 1280x360
  # of content inside its 800-line frame, showing whatever was on screen. The
  # niri virtual output declared in custom.niri.virtualOutputs is turned on and
  # resized for the client, and the game is moved onto it, leaving DP-2 alone.
  custom.steamStreamMode = {
    enable = true;
    # niriPackage is set from the host config, where the patched package the
    # session actually runs is in scope — `niri msg` has to match the running
    # compositor, and virtual output support is a patch rather than upstream.
    # Taken from the output's own declaration so the watcher cannot resize it
    # to a shape the output was not declared with.
    defaultWidth = config.custom.niri.virtualOutputs.steam.width;
    defaultHeight = config.custom.niri.virtualOutputs.steam.height;
    refresh = config.custom.niri.virtualOutputs.steam.refresh;
  };

  home.packages = [
    pkgs.nbt-studio
    # Provides uhk-switch-keymap, used by the pre_launch/post_exit hooks
    # below. The gamescope shim below is symlinked separately by name
    # rather than exposed via this package, so this doesn't duplicate it.
    inputs.steam-command-runner.packages.${pkgs.stdenv.hostPlatform.system}.default
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

    # Follows the active game with the matching UHK keymap: HD2's stratagem
    # macros while it's running, back to the daily-driver QWERTY keymap on
    # exit. uhk-switch-keymap auto-discovers the connected UHK, so this
    # doesn't need a device id.
    games."553850" = {
      hooks.pre_launch.command = "uhk-switch-keymap HD2";
      hooks.post_exit.command = "uhk-switch-keymap QWR";
    };
  };

  programs.uhkKeymaps.enable = true;

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
