{ config, lib, pkgs, ... }:
let
  cfg = config.modules.vr;

  seedVrMonitorMimeDefaultScript = pkgs.writeText "seed-vrmonitor-mime-default.py" ''
    import os

    path = "${config.xdg.configHome}/mimeapps.list"
    key = "x-scheme-handler/vrmonitor"
    # Steam names the handler after whichever SteamVR install it last
    # launched; list both so xdg-open has a candidate either way.
    value = "valve-vrmonitor.desktop;valve-URI-vrmonitor.desktop;"
    section = "[Default Applications]"


    def mtime():
        # A single call, not exists()-then-getmtime(): that pair has its own
        # TOCTOU window (the file can vanish between the two), which would
        # raise FileNotFoundError and crash the whole activation script --
        # worse than the race this function exists to detect. st_mtime_ns
        # rather than getmtime()'s float seconds: a double's precision
        # leaves only microsecond-ish resolution at current Unix timestamps,
        # coarser than what the filesystem actually tracks.
        try:
            return os.stat(path).st_mtime_ns
        except FileNotFoundError:
            return None


    def seed(lines):
        """Returns the new line list, or None if the key is already set."""
        section_start = None
        for i, line in enumerate(lines):
            if line.strip() == section:
                section_start = i
                break

        if section_start is None:
            if lines and lines[-1].strip():
                lines.append("")
            return lines + [section, f"{key}={value}"]

        section_end = len(lines)
        for i in range(section_start + 1, len(lines)):
            if lines[i].strip().startswith("["):
                section_end = i
                break
        already_set = any(
            lines[i].strip().split("=", 1)[0].strip() == key
            for i in range(section_start + 1, section_end)
        )
        if already_set:
            return None
        return lines[: section_start + 1] + [f"{key}={value}"] + lines[section_start + 1 :]


    # Another process (Thunderbird, a GTK "always open with" pick, ...) can
    # write this same file between our read and our write. Re-checking mtime
    # right before the atomic rename, and retrying from a fresh read if it
    # moved, keeps that window effectively zero without needing every writer
    # to cooperate with a lock -- which they don't.
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for _attempt in range(5):
        before = mtime()
        lines = []
        try:
            with open(path) as fh:
                lines = fh.read().splitlines()
        except FileNotFoundError:
            pass

        new_lines = seed(lines)
        if new_lines is None:
            break

        tmp_path = f"{path}.new"
        with open(tmp_path, "w") as fh:
            fh.write("\n".join(new_lines) + "\n")

        if mtime() == before:
            os.replace(tmp_path, path)
            break
        os.remove(tmp_path)
    else:
        raise SystemExit("seed-vrmonitor-mime-default: gave up after 5 concurrent-write retries")
  '';
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

    # SteamVR's own UI (its "Restart SteamVR" button) shells out to a
    # vrmonitor:// URI. With no default handler set for it, xdg-open falls
    # through to a portal "Open With" chooser that reads a mimeinfo.cache
    # nothing ever regenerates for ~/.local/share/applications (Steam drops
    # its x-scheme-handler/vrmonitor .desktop file there at runtime, outside
    # home-manager's activation, so the cache never picks it up) -- shows
    # "No Apps available" even though a handler is sitting right there.
    #
    # Deliberately not xdg.mimeApps.enable (which would make home-manager
    # own the whole of mimeapps.list as a read-only symlink): several apps
    # (Thunderbird's mailto handler, Discord's per-server PWA shortcuts)
    # write their own entries into that file at runtime with
    # machine-generated ids, and a read-only file would permanently stop any
    # of them from ever registering a new one again. Instead this seeds just
    # the one line into the live, still-mutable file -- idempotent, and never
    # touches a key that's already there, so it doesn't fight whatever wrote
    # the rest of the file.
    # Best-effort: a failed seed (e.g. exhausting its concurrent-write
    # retries) shouldn't fail the whole home-manager activation over a QoL
    # default, so || true rather than letting `run` propagate the exit code.
    home.activation.seedVrMonitorMimeDefault = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.python3}/bin/python3 ${seedVrMonitorMimeDefaultScript} || true
    '';
  };
}
