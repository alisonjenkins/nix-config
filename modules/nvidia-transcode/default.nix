{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.nvidiaTranscode;

  # NVENC concurrent-session-limit removal patterns, vendored from
  # keylase/nvidia-patch `patch.sh` (rev ad462e42, 2026-07-13). Keyed by EXACT
  # driver version; the value is a `s/OLD/NEW/g` byte-substitution applied to
  # libnvidia-encode.so with `perl -0777` (see below). Each removes the session
  # cap by rewriting `call; mov r14d,eax; test eax,eax` → `call; sub eax,eax;
  # mov r14d,eax`, forcing the live-session count to 0 and dropping the limit
  # branch. A pattern is only valid for its exact build, hence the per-version
  # table + the substitution-count guard. Re-vendor to add versions:
  #   grep -E '^\s*\["58' patch.sh
  #
  # NOTE 580.173.02: not published by keylase (their newest 580 is 580.159.04),
  # but this exact pattern was verified to match the shipped
  # libnvidia-encode.so.580.173.02 EXACTLY ONCE via `perl -0777` — the 580
  # branch's call-displacement (\xe8\x81\x2e\xfe\xff) is byte-stable across the
  # whole series. (Beware: `grep -P` FALSELY reports no match on these patterns
  # — invalid-UTF-8 bytes silently fail PCRE; perl is the ground truth.)
  keylasePatchList = {
    "580.65.06" =
      ''s/\xe8\x81\x2e\xfe\xff\x41\x89\xc6\x85\xc0\x0f\x85\xa6\x00\x00\x00\x4c/\xe8\x81\x2e\xfe\xff\x29\xc0\x41\x89\xc6\x90\x90\x90\x90\x90\x90\x4c/g'';
    "580.76.05" =
      ''s/\xe8\x81\x2e\xfe\xff\x41\x89\xc6\x85\xc0\x0f\x85\xa6\x00\x00\x00\x4c/\xe8\x81\x2e\xfe\xff\x29\xc0\x41\x89\xc6\x90\x90\x90\x90\x90\x90\x4c/g'';
    "580.82.07" =
      ''s/\xe8\x81\x2e\xfe\xff\x41\x89\xc6\x85\xc0\x0f\x85\xa6\x00\x00\x00\x4c/\xe8\x81\x2e\xfe\xff\x29\xc0\x41\x89\xc6\x90\x90\x90\x90\x90\x90\x4c/g'';
    "580.82.09" =
      ''s/\xe8\x81\x2e\xfe\xff\x41\x89\xc6\x85\xc0\x0f\x85\xa6\x00\x00\x00\x4c/\xe8\x81\x2e\xfe\xff\x29\xc0\x41\x89\xc6\x90\x90\x90\x90\x90\x90\x4c/g'';
    "580.95.05" =
      ''s/\xe8\x81\x2e\xfe\xff\x41\x89\xc6\x85\xc0\x0f\x85\xa6\x00\x00\x00\x4c/\xe8\x81\x2e\xfe\xff\x29\xc0\x41\x89\xc6\x90\x90\x90\x90\x90\x90\x4c/g'';
    "580.105.08" =
      ''s/\xe8\x81\x2e\xfe\xff\x41\x89\xc6\x85\xc0\x0f\x85\xa6\x00\x00\x00\x4c/\xe8\x81\x2e\xfe\xff\x29\xc0\x41\x89\xc6\x90\x90\x90\x90\x90\x90\x4c/g'';
    "580.119.02" =
      ''s/\xe8\x81\x2e\xfe\xff\x41\x89\xc6\x85\xc0/\xe8\x81\x2e\xfe\xff\x29\xc0\x41\x89\xc6/g'';
    "580.126.09" =
      ''s/\xe8\x81\x2e\xfe\xff\x41\x89\xc6\x85\xc0/\xe8\x81\x2e\xfe\xff\x29\xc0\x41\x89\xc6/g'';
    "580.142" =
      ''s/\xe8\x81\x2e\xfe\xff\x41\x89\xc6\x85\xc0/\xe8\x81\x2e\xfe\xff\x29\xc0\x41\x89\xc6/g'';
    "580.159.03" =
      ''s/\xe8\x81\x2e\xfe\xff\x41\x89\xc6\x85\xc0/\xe8\x81\x2e\xfe\xff\x29\xc0\x41\x89\xc6/g'';
    "580.159.04" =
      ''s/\xe8\x81\x2e\xfe\xff\x41\x89\xc6\x85\xc0/\xe8\x81\x2e\xfe\xff\x29\xc0\x41\x89\xc6/g'';
    # Not from keylase — verified locally against the shipped .so (see NOTE above).
    "580.173.02" =
      ''s/\xe8\x81\x2e\xfe\xff\x41\x89\xc6\x85\xc0/\xe8\x81\x2e\xfe\xff\x29\xc0\x41\x89\xc6/g'';
  };

  driverVersion = cfg.driverPackage.version;
  patchExpr = cfg.nvencPatchList.${driverVersion} or null;
  # Both `nvencUnlock` requested AND a pattern exists for this exact driver.
  # If unlock is on but no pattern exists, the assertion below blocks the build
  # (so `effectiveDriver` never tries to interpolate a null pattern).
  unlockActive = cfg.nvencUnlock && patchExpr != null;

  # Rebuild the driver with libnvidia-encode.so byte-patched to drop the NVENC
  # session cap. Uses `perl -0777` (whole-file slurp), NOT `sed`: sed is
  # line-oriented and corrupts binaries (splits on \x0a, appends a trailing
  # newline), which also defeats a naive cmp-based guard. The substitution
  # COUNT is the guard — perl exits non-zero when the vendored pattern matches
  # 0 sites, so a stale/wrong pattern fails the build loudly instead of
  # shipping an unpatched lib that looks patched. Nothing here needs the GPU;
  # it operates on the shipped .so. `cat >` overwrite preserves the file's
  # mode + inode (the versioned .so is the target of the libnvidia-encode.so.1
  # soname symlink).
  patchedDriver = cfg.driverPackage.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.perl ];
    postFixup = (old.postFixup or "") + ''
      enc="$out/lib/libnvidia-encode.so.${driverVersion}"
      if [ ! -f "$enc" ]; then
        echo "nvenc-unlock: $enc not found — cannot apply keylase patch" >&2
        exit 1
      fi
      if perl -0777 -pe 'BEGIN { $c = 0 } $c += (${patchExpr}); END { exit ($c > 0 ? 0 : 1) }' "$enc" > "$enc.new"; then
        cat "$enc.new" > "$enc"
        rm -f "$enc.new"
        echo "nvenc-unlock: patched $enc (keylase, driver ${driverVersion})"
      else
        rm -f "$enc.new"
        echo "nvenc-unlock: pattern for ${driverVersion} matched 0 sites in the shipped libnvidia-encode.so — the vendored pattern is stale for this build; refusing to ship an unpatched driver." >&2
        exit 1
      fi
    '';
  });

  effectiveDriver = if unlockActive then patchedDriver else cfg.driverPackage;
in
{
  options.modules.nvidiaTranscode = {
    enable = lib.mkEnableOption "headless NVIDIA NVENC transcode stack for a k3s node";

    driverPackage = lib.mkOption {
      type = lib.types.package;
      default = config.boot.kernelPackages.nvidiaPackages.production;
      defaultText = lib.literalExpression "config.boot.kernelPackages.nvidiaPackages.production";
      description = ''
        NVIDIA driver package. Defaults to the `production` branch, which is one
        major behind `stable` and — as of this writing — is the 580 series, the
        LAST branch to support Maxwell/Pascal/Volta. See `requirePascalDriver`.
      '';
    };

    requirePascalDriver = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Assert the selected driver is older than the 590 branch. NVIDIA 590
        DROPPED Maxwell/Pascal/Volta support, so a GTX 1070 (Pascal) goes dark
        on 590+. This turns a future `production`→590 bump into a loud build
        failure instead of a silently non-functional GPU. Set false only for a
        Turing-or-newer card.
      '';
    };

    persistenced = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run `nvidia-persistenced` so the driver stays initialised with no X
        server / no display attached. Keeps the GPU responsive for on-demand
        transcodes (the declarative equivalent of `nvidia-smi -pm 1`) and avoids
        per-stream driver re-init latency.
      '';
    };

    containerToolkit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable the NVIDIA Container Toolkit + CDI so k3s' bundled containerd can
        expose the GPU to pods. k3s auto-detects `nvidia-container-runtime` on
        PATH at startup and templates a `nvidia` containerd runtime. The k8s
        `RuntimeClass` object and the device-plugin DaemonSet that advertises
        `nvidia.com/gpu` are cluster-layer manifests (GitOps), not node config.
      '';
    };

    nvencUnlock = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Remove the NVENC concurrent-session cap by byte-patching
        libnvidia-encode.so at build time (keylase/nvidia-patch). Consumer
        GeForce drivers otherwise limit simultaneous NVENC encode sessions
        (currently 5 on recent branches) — plenty for typical load, so leave
        this off unless you genuinely need more concurrent transcodes.

        Requires a pattern for the EXACT `driverPackage.version` in
        `nvencPatchList`; if absent the build FAILS with the covered versions
        listed (rather than silently shipping an unpatched driver). The patch is
        verified to actually change the library, so a stale pattern also fails
        the build. Toggling this off rebuilds the stock driver — fully
        reversible, no on-disk state.
      '';
    };

    nvencPatchList = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = keylasePatchList;
      defaultText = lib.literalExpression "keylase/nvidia-patch 580-series patterns";
      description = ''
        Map of exact NVIDIA driver version → `sed` byte-substitution applied to
        libnvidia-encode.so to lift the NVENC session cap, vendored from
        keylase/nvidia-patch. Extend this (e.g. `// { "580.173.02" = "s/.../.../g"; }`)
        to cover a driver version upstream has not published yet, or once it does.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.requirePascalDriver || lib.versionOlder driverVersion "590";
        message =
          "modules.nvidiaTranscode: driver ${driverVersion} is 590+, which dropped "
          + "Pascal (GTX 1070) support. Pin nvidiaPackages to the 580 branch, or set "
          + "requirePascalDriver = false for a Turing-or-newer card.";
      }
      {
        assertion = !cfg.nvencUnlock || patchExpr != null;
        message =
          "modules.nvidiaTranscode.nvencUnlock is on but nvencPatchList has no keylase "
          + "byte-pattern for driver ${driverVersion}. Covered versions: "
          + "${lib.concatStringsSep ", " (lib.attrNames cfg.nvencPatchList)}. "
          + "Add an entry for ${driverVersion} (once keylase/nvidia-patch publishes one) "
          + "via nvencPatchList, or pin driverPackage to a covered version.";
      }
    ];

    # VA-API/render-node userspace + the kernel-module glue the driver needs.
    hardware.graphics.enable = true;

    # Registers the NVIDIA kmod + userspace. Does NOT start an X server; this is
    # the standard way to load the proprietary driver on a headless host.
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      package = effectiveDriver;
      # Pascal predates the open-GPU kernel module (Turing+ only) — the open
      # kmod will not bind a GTX 1070, so force the proprietary module.
      open = false;
      modesetting.enable = true;
      nvidiaPersistenced = cfg.persistenced;
    };

    hardware.nvidia-container-toolkit.enable = cfg.containerToolkit;
  };
}
