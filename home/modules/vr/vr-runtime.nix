{ config, lib, pkgs, ... }:
let
  cfg = config.modules.vr;

  # Runtime selection between WiVRn (Monado, serving the Quest over the LAN)
  # and SteamVR (needed by a Steam Frame, and by titles that want SteamVR
  # itself). This used to be a build-time choice via
  # modules.vr.enableOpenSourceVR, which is why the live state drifted:
  # OpenXR pointed at WiVRn while openvrpaths.vrpath listed SteamVR first.
  #
  # The VR_RUNTIME_* environment overrides exist so the test harness can drive
  # this against a throwaway HOME.
  vr-runtime = pkgs.writeShellApplication {
    name = "vr-runtime";
    runtimeInputs = with pkgs; [ coreutils python3 systemd ];
    text = ''
      WIVRN_JSON="''${VR_RUNTIME_WIVRN_JSON:-${pkgs.wivrn}/share/openxr/1/openxr_wivrn.json}"
      STEAMVR_ROOT="''${VR_RUNTIME_STEAMVR_ROOT:-${cfg.steamvrRoot}}"
      STEAM_ROOT="''${VR_RUNTIME_STEAM_ROOT:-${cfg.steamRoot}}"
      OPENCOMPOSITE_ROOT="''${VR_RUNTIME_OPENCOMPOSITE_ROOT:-${pkgs.opencomposite}/lib/opencomposite}"

      OPENXR_FILE="$HOME/.config/openxr/1/active_runtime.json"
      OPENVR_FILE="$HOME/.config/openvr/openvrpaths.vrpath"

      # Skipped during home-manager activation, which re-applies the current
      # runtime to refresh it and must not start or stop services as a side
      # effect of a rebuild. Also skipped by the test harness.
      svc() {
        if [ -n "''${VR_RUNTIME_SKIP_SERVICE:-}" ]; then
          return 0
        fi
        systemctl --user "$@" wivrn.service || true
      }

      # Puts a manifest at $OPENXR_FILE by renaming rather than copying onto
      # it. That path may still be a symlink into the Nix store from when it
      # was managed by xdg.configFile, and `cp` onto a symlink writes through
      # it -- into a read-only store, so the switch fails and the file can
      # never heal itself. Renaming replaces the link.
      install_openxr() {
        cp --no-preserve=mode "$1" "$OPENXR_FILE.new"
        mv -f "$OPENXR_FILE.new" "$OPENXR_FILE"
      }

      # Rewrites only the runtime list. Existing config and log paths are kept,
      # because on this host they point at a separate mount and are not
      # derivable from $HOME; otherwise they fall back to the Steam root.
      write_openvrpaths() {
        mkdir -p "$(dirname "$OPENVR_FILE")"
        python3 - "$OPENVR_FILE" "$STEAM_ROOT" "$@" <<'PY'
import json, os, sys

path, steam_root, *runtimes = sys.argv[1:]

existing = {}
if os.path.exists(path):
    try:
        with open(path) as fh:
            existing = json.load(fh)
    except (ValueError, OSError):
        existing = {}


def keep(paths):
    """Reuse previously recorded paths, rejecting nonsense.

    A Steam config or log directory is never inside the Nix store. An earlier
    revision derived these from the runtime path, which on the WiVRn branch is
    the OpenComposite store path, and so wrote /nix/store/config. Rejecting
    store paths here means a file written by that revision self-heals on the
    next switch instead of preserving the garbage forever.
    """
    if not isinstance(paths, list) or not paths:
        return None
    if any(not isinstance(q, str) or q.startswith("/nix/store/") for q in paths):
        return None
    return paths


external = existing.get("external_drivers")
if not isinstance(external, list):
    # vrpathreg expects a list here. Carrying a missing key through as JSON
    # null broke consumers that assume an array, and the manifest this
    # replaced shipped [].
    external = []

doc = {
    "config": keep(existing.get("config")) or [os.path.join(steam_root, "config")],
    "external_drivers": external,
    "jsonid": "vrpathreg",
    "log": keep(existing.get("log")) or [os.path.join(steam_root, "logs")],
    "runtime": list(runtimes),
    "version": 1,
}

# Written beside the target and renamed over it, never opened for writing in
# place. This path may still be a symlink into the Nix store from when it was
# managed by xdg.configFile; opening that with "w" follows the link and fails
# on a read-only store, so the file could never heal itself. Renaming replaces
# the symlink instead of chasing it, and is atomic for anything reading
# concurrently -- wivrn-server rewrites this file at every startup.
tmp = path + ".new"
with open(tmp, "w") as fh:
    json.dump(doc, fh, indent=3)
    fh.write("\n")
os.replace(tmp, path)
PY
      }

      case "''${1:-status}" in
        wivrn)
          mkdir -p "$(dirname "$OPENXR_FILE")"
          install_openxr "$WIVRN_JSON"
          # wivrn-server rewrites openvrpaths.vrpath at every startup from its
          # built-in OVR_COMPAT_SEARCH_PATH, so OpenComposite is written here
          # only as a sane resting state — wivrn owns the file while running.
          write_openvrpaths "$OPENCOMPOSITE_ROOT"
          svc start
          echo "vr-runtime: now wivrn"
          ;;
        steamvr)
          svc stop
          mkdir -p "$(dirname "$OPENXR_FILE")"
          # SteamVR ships its own OpenXR manifest, which carries
          # VALVE_runtime_is_steamvr. Prefer it over a hand-written one so the
          # manifest stays correct across SteamVR updates.
          if [ -f "$STEAMVR_ROOT/steamxr_linux64.json" ]; then
            install_openxr "$STEAMVR_ROOT/steamxr_linux64.json"
          else
            cat > "$OPENXR_FILE.new" <<EOF
{
  "file_format_version": "1.0.0",
  "runtime": {
    "VALVE_runtime_is_steamvr": true,
    "library_path": "$STEAMVR_ROOT/bin/linux64/vrclient.so",
    "name": "SteamVR"
  }
}
EOF
            mv -f "$OPENXR_FILE.new" "$OPENXR_FILE"
          fi
          write_openvrpaths "$STEAMVR_ROOT" "$OPENCOMPOSITE_ROOT"
          echo "vr-runtime: now steamvr"
          ;;
        status)
          if [ ! -e "$OPENXR_FILE" ]; then
            echo "vr-runtime: unset (no active_runtime.json)"
            exit 0
          fi
          name="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['runtime'].get('name','unknown'))" "$OPENXR_FILE")"
          case "$name" in
            Monado | *wivrn* | *WiVRn*) echo "vr-runtime: wivrn ($name)" ;;
            SteamVR | *Steam*) echo "vr-runtime: steamvr ($name)" ;;
            *) echo "vr-runtime: unknown ($name)" ;;
          esac
          ;;
        *)
          echo "usage: vr-runtime [wivrn|steamvr|status]" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.modules.vr = {
    steamRoot = lib.mkOption {
      type = lib.types.str;
      default = "\${HOME}/.local/share/Steam";
      description = ''
        Root of the Steam installation. Supplies the config and log paths
        recorded in openvrpaths.vrpath when the file does not already carry
        usable ones.
      '';
    };

    steamvrRoot = lib.mkOption {
      type = lib.types.str;
      default = "\${HOME}/.local/share/Steam/steamapps/common/SteamVR";
      description = ''
        Filesystem path to the SteamVR installation, used when switching the
        active OpenXR and OpenVR runtimes to SteamVR.
      '';
    };

    runtimeSwitcherPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = vr-runtime;
      description = ''
        The vr-runtime switcher derivation. Internal: exposed only so the
        seeding activation script in ./default.nix can reference the same
        derivation this module installs, without duplicating its definition.
      '';
    };
  };

  config = lib.mkIf pkgs.stdenv.isLinux {
    home.packages = [ vr-runtime ];
  };
}
