{ pkgs, lib, ... }:
let
  # Sunshine's detached commands run from the Sunshine user service, which
  # does not inherit the niri session's WAYLAND_DISPLAY, so it has to be
  # recovered. The imperative scripts these replace hardcoded wayland-1,
  # which is only correct by accident of startup ordering.
  resolveWayland = ''
    XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export XDG_RUNTIME_DIR

    if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
      for sock in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
        case "$sock" in
          *.lock) continue ;;
        esac
        [ -S "$sock" ] || continue
        WAYLAND_DISPLAY="$(basename "$sock")"
        export WAYLAND_DISPLAY
        break
      done
    fi

    if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
      echo "no wayland socket found in $XDG_RUNTIME_DIR" >&2
      exit 1
    fi
  '';

  # gamescope is deliberately absent from runtimeInputs. writeShellApplication
  # prepends runtimeInputs to PATH, which would shadow the steam-command-runner
  # shim at ~/.local/bin/gamescope that this launch is supposed to go through.
  # Resolving gamescope from the inherited PATH preserves the interception.
  sunshine-gamescope = pkgs.writeShellApplication {
    name = "sunshine-gamescope";
    runtimeInputs = with pkgs; [ coreutils util-linux ];
    text = ''
      ${resolveWayland}

      case "''${1:-1080p}" in
        1080p|1080) WIDTH=1920; HEIGHT=1080 ;;
        1440p|1440) WIDTH=2560; HEIGHT=1440 ;;
        *)
          echo "unknown resolution '$1', using 1080p" >&2
          WIDTH=1920; HEIGHT=1080
          ;;
      esac

      # This Steam runs inside a headless gamescope session, where the flags
      # tuned for the desktop session are wrong. -pipewire in particular forces
      # portal desktop capture, and there is no desktop here to capture: the
      # portal hands back a 0x0 stream and the client hangs. The Steam wrapper
      # in modules/desktop honours this variable by execing Steam without them.
      export STEAM_NO_EXTRA_FLAGS=1

      # Backgrounded, matching the script this replaces: Sunshine launches
      # this as a detached command and the wrapper is expected to return
      # immediately rather than stay attached to the gamescope session.
      # setsid detaches from Sunshine's process group so Sunshine's own exit
      # does not tear the session down.
      setsid gamescope \
        -W "$WIDTH" -H "$HEIGHT" -w "$WIDTH" -h "$HEIGHT" \
        -r 120 --force-windows-fullscreen -e \
        -- steam -gamepadui &
    '';
  };

  sunshine-steam-bp = pkgs.writeShellApplication {
    name = "sunshine-steam-bp";
    runtimeInputs = with pkgs; [ coreutils util-linux ];
    text = ''
      ${resolveWayland}

      # Backgrounded rather than exec'd, for the same reason as
      # sunshine-gamescope: Sunshine runs this as a detached command and
      # expects it to return. `exec` kept the wrapper attached until Steam
      # exited, which is a session Sunshine thinks is still starting.
      #
      # No STEAM_NO_EXTRA_FLAGS here, deliberately. This opens Big Picture in
      # the desktop session — the same session the extra flags are tuned for —
      # so if this is what starts Steam, it should start with them. The opt-out
      # exists for Steam launched somewhere with no desktop to capture.
      setsid steam steam://open/bigpicture &
    '';
  };
in
{
  config = lib.mkIf pkgs.stdenv.isLinux {
    home.packages = [ sunshine-gamescope sunshine-steam-bp ];
  };
}
