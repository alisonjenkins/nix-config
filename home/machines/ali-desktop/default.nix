{ pkgs, inputs, ... }: {
  imports = [
    ./easyeffects
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
