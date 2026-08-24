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
      # Re-applies whatever runtime is currently selected, rather than only
      # seeding when nothing is. Re-applying is what refreshes the store paths
      # written into openvrpaths.vrpath across a nixpkgs bump, and what lets a
      # file written by an older revision heal. Seeding alone could never
      # reach either case, because it skips as soon as the file exists.
      #
      # The current selection is read back rather than taken from
      # enableOpenSourceVR, so a machine switched to SteamVR by hand is not
      # dragged back to WiVRn by an unrelated rebuild.
      vrRuntimeStatus="$(VR_RUNTIME_SKIP_SERVICE=1 ${lib.getExe cfg.runtimeSwitcherPackage} status 2>/dev/null || true)"
      case "$vrRuntimeStatus" in
        *wivrn*) vrRuntimeTarget=wivrn ;;
        *steamvr*) vrRuntimeTarget=steamvr ;;
        *) vrRuntimeTarget=${if cfg.enableOpenSourceVR then "wivrn" else "steamvr"} ;;
      esac
      run env VR_RUNTIME_SKIP_SERVICE=1 ${lib.getExe cfg.runtimeSwitcherPackage} \
        "$vrRuntimeTarget" || true
    '';
  };
}
