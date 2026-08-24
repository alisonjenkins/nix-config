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
      OPENCOMPOSITE_ROOT="''${VR_RUNTIME_OPENCOMPOSITE_ROOT:-${pkgs.opencomposite}/lib/opencomposite}"

      OPENXR_FILE="$HOME/.config/openxr/1/active_runtime.json"
      OPENVR_FILE="$HOME/.config/openvr/openvrpaths.vrpath"

      svc() {
        if [ -n "''${VR_RUNTIME_DRY_RUN:-}" ]; then
          return 0
        fi
        systemctl --user "$@" wivrn.service || true
      }

      # Rewrites only the runtime list. The config and log paths are preserved
      # from the existing file because the Steam library on this host lives on
      # a separate mount, so they are not derivable from $HOME.
      write_openvrpaths() {
        mkdir -p "$(dirname "$OPENVR_FILE")"
        python3 - "$OPENVR_FILE" "$@" <<'PY'
import json, os, sys

path, *runtimes = sys.argv[1:]

existing = {}
if os.path.exists(path):
    try:
        with open(path) as fh:
            existing = json.load(fh)
    except (ValueError, OSError):
        existing = {}

steam_root = os.path.dirname(os.path.dirname(os.path.dirname(runtimes[0])))
doc = {
    "config": existing.get("config") or [os.path.join(steam_root, "config")],
    "external_drivers": existing.get("external_drivers"),
    "jsonid": "vrpathreg",
    "log": existing.get("log") or [os.path.join(steam_root, "logs")],
    "runtime": list(runtimes),
    "version": 1,
}

with open(path, "w") as fh:
    json.dump(doc, fh, indent=3)
    fh.write("\n")
PY
      }

      case "''${1:-status}" in
        wivrn)
          mkdir -p "$(dirname "$OPENXR_FILE")"
          cp --no-preserve=mode "$WIVRN_JSON" "$OPENXR_FILE"
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
            cp --no-preserve=mode "$STEAMVR_ROOT/steamxr_linux64.json" "$OPENXR_FILE"
          else
            cat > "$OPENXR_FILE" <<EOF
{
  "file_format_version": "1.0.0",
  "runtime": {
    "VALVE_runtime_is_steamvr": true,
    "library_path": "$STEAMVR_ROOT/bin/linux64/vrclient.so",
    "name": "SteamVR"
  }
}
EOF
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
