{ config, lib, pkgs, ... }:
let
  cfg = config.modules.vr;
  jsonFormat = pkgs.formats.json { };

  mergeSteamvrSettingsScript = pkgs.writeText "merge-steamvr-settings.py" ''
    import json
    import os
    import sys

    path = sys.argv[1]
    declared = json.loads(sys.argv[2])


    def merge(existing, wanted):
        if isinstance(existing, dict) and isinstance(wanted, dict):
            result = dict(existing)
            for key, value in wanted.items():
                result[key] = merge(existing.get(key), value)
            return result
        return wanted


    def mtime():
        # Same TOCTOU-avoiding single-stat pattern as
        # seed-vrmonitor-mime-default.py: vrserver rewrites this file
        # constantly while SteamVR is running (GpuSpeed calibration,
        # LastKnown HMD info, safe-mode flags, ...), so a plain
        # read-modify-write can silently lose whichever side loses the race.
        try:
            return os.stat(path).st_mtime_ns
        except FileNotFoundError:
            return None


    os.makedirs(os.path.dirname(path), exist_ok=True)
    for _attempt in range(5):
        before = mtime()
        try:
            with open(path) as fh:
                existing = json.load(fh)
        except (FileNotFoundError, ValueError):
            existing = {}

        merged = merge(existing, declared)
        if merged == existing:
            break

        tmp_path = f"{path}.new"
        with open(tmp_path, "w") as fh:
            json.dump(merged, fh, indent=3)
            fh.write("\n")

        if mtime() == before:
            os.replace(tmp_path, path)
            break
        os.remove(tmp_path)
    else:
        raise SystemExit(
            "merge-steamvr-settings: gave up after 5 concurrent-write retries"
        )
  '';
in
{
  options.modules.vr.steamvrSettings = lib.mkOption {
    type = jsonFormat.type;
    default = { };
    example = {
      driver_vrlink = {
        enableEncryption = true;
        enableQoS = true;
      };
    };
    description = ''
      Settings to merge into steamvr.vrsettings on every activation.

      This is a merge, not a symlink: SteamVR rewrites this file constantly
      at runtime (GpuSpeed calibration, LastKnown HMD info, safe-mode flags,
      dashboard state, ...), so the file has to stay a normal writable file.
      Only the keys declared here are enforced; everything else SteamVR or
      the SteamVR UI has written is left alone. A key nested under a
      declared section (e.g. driver_vrlink.useSharpening, when only
      enableEncryption and enableQoS are declared) is preserved the same
      way.

      Re-asserted on every home-manager activation, so a value SteamVR or
      its UI flips back (e.g. after a driver update resets a default) is
      corrected on the next switch rather than silently drifting.

      ## driver_vrlink reference (2.18.2, confirmed 2026-10-02)

      Full defaults shipped in
      drivers/vrlink/resources/settings/default.vrsettings. None of these
      are declared here unless a host's config says so above -- listed for
      reference when deciding whether a new one is worth pinning, not as a
      recommendation to set them.

      User-exposed, quality/perf (not pinned by any host yet -- stock
      values, nobody has tuned these):
        displayFrequency = 90            # Hz sent to the headset
        renderWidth = 2048                renderHeight = 2048   # per-eye render res
        encodeWidth = 1536                # encode res before upscale
        automaticBandwidth = true         targetBandwidth = 200 # Mbit cap when automatic is off
        "10bit" = true                    # 10-bit color encode
        useSharpening = false             sharpeningStrength = 0.2
        automaticStreamFormatWidth = true streamFormatWidth = 1024 # foveated stream width
        wirelessShutdownTimeout = 30      # seconds idle before auto-shutdown

      User-exposed, feature toggles:
        enableHandTracking = true         allowVolumeSync = true
        allowMultipleLinks = true         enableHmdAutoConnect = true
        useOSC = false                    useOSCFace = false
        shareEyeTrackingData = false      showAdvancedGraphs = false
        enableQoS = false                 enableEncryption = false  # pinned true on ali-desktop

      Internal/advanced -- not in the SteamVR UI, no documented semantics,
      riskier to touch:
        enable8814AP = true               enableNAT = false
        loadPriority = 110                spoofAtStart = false
        enableTimedRetry = 1              reqEncMode = "auto"
        forceOpenMode = false             watchForShaderChanges = false
        forceBaselineVideoFEC = false     asyncSend = false
        asyncStartEncode = true           backoffRecoveryCoefficient = 3.5
        enableAmfEncoder = true           OSCInPort = 9016
        OSCOutPort = 9000
    '';
  };

  config = lib.mkIf (pkgs.stdenv.isLinux && cfg.steamvrSettings != { }) {
    home.activation.mergeSteamvrSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe pkgs.python3} ${mergeSteamvrSettingsScript} \
        "${cfg.steamRoot}/config/steamvr.vrsettings" \
        ${lib.escapeShellArg (builtins.toJSON cfg.steamvrSettings)} \
        || true
    '';
  };
}
