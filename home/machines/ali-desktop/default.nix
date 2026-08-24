{ pkgs, inputs, ... }: {
  imports = [
    ./easyeffects
    ../../programs/linux-only/steam-command-runner
    ../../programs/linux-only/sunshine-wrappers
    # Disabled location-based audio settings (desktop doesn't move)
    # ./location-detection
    # ./audio-context
  ];

  modules.vr.enableOpenSourceVR = true;

  home.packages = [
    pkgs.nbt-studio

    # Steam Remote Play captures a niri output, not a window, so the streamed
    # frame carries the whole 5120x1440 panel — half game, half desktop —
    # unless DP-2 is narrowed for the duration of the session. Sunshine does
    # this per-application via prep-cmd; Steam Remote Play has no equivalent
    # hook, so it is driven by hand either side of a session.
    (pkgs.writeShellApplication {
      name = "stream-mode";
      runtimeInputs = [ pkgs.niri ];
      text = ''
        # Mode strings must match what DP-2 advertises exactly; niri msg fails
        # rather than falling back on a near miss.
        case "''${1:-}" in
          deck)  mode="1280x800@59.810" ;;   # the Deck's native panel, 1:1, no scaling
          1080p) mode="1920x1080@120.000" ;;
          1440p) mode="2560x1440@119.998" ;;
          off)   mode="5120x1440@119.999" ;; # the panel's own preferred mode
          *)
            echo "usage: stream-mode [deck|1080p|1440p|off]" >&2
            exit 2
            ;;
        esac
        niri msg output DP-2 mode "$mode"
        echo "stream-mode: DP-2 now $mode"
      '';
    })
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
