{ config, lib, pkgs, ... }:
let
  cfg = config.modules.vr;
in
{
  imports = [ ./vr-runtime.nix ];

  options.modules.vr = {
    enableOpenSourceVR = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install the open-source VR stack (WiVRn as the OpenXR runtime,
        OpenComposite as the OpenVR runtime) and seed it as the initial
        runtime selection on a machine that has never chosen one.

        This no longer *pins* the active runtime. Both files have to be
        writable for `vr-runtime` to switch between WiVRn and SteamVR, so
        home-manager seeds them once and then leaves them alone. A Steam Frame
        streams PC VR through SteamVR, so the machine has to be able to hold
        both runtimes and pick between them without a rebuild.
      '';
    };
  };

  config = lib.mkIf pkgs.stdenv.isLinux {
    # Seeds the runtime selection only when nothing has chosen one yet.
    # Deliberately not xdg.configFile: that produces read-only store symlinks,
    # which is what left the live state inconsistent — OpenXR resolved to
    # WiVRn while openvrpaths.vrpath listed SteamVR first, and nothing short
    # of a rebuild could reconcile them.
    home.activation.seedVrRuntime = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -e "$HOME/.config/openxr/1/active_runtime.json" ]; then
        run ${lib.getExe cfg.runtimeSwitcherPackage} \
          ${if cfg.enableOpenSourceVR then "wivrn" else "steamvr"} || true
      fi
    '';
  };
}
