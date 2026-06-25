{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.modules.niks3CachePush;
  niks3 = inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.default;
  scripts = import ./scripts.nix { inherit pkgs lib cfg niks3; };
in
{
  options.modules.niks3CachePush = {
    enable = lib.mkEnableOption "niks3 binary cache auto-upload (niks3-hook)";

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://api.nixcache.org";
      description = "niks3 server URL to push store paths to";
    };

    cacheUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://cache.nixcache.org";
      description = ''
        Public read URL for the CDN-fronted S3 bucket. The backfill script
        sends parallel HEAD requests here to check whether a path's narinfo
        is already cached, so it only spends rate-limited push budget on
        paths that are actually missing. Distinct from `serverUrl`, which
        points at the niks3 API.
      '';
    };

    socketPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/niks3/upload-to-cache.sock";
      description = ''
        Unix stream socket the post-build-hook (`niks3-hook send`) writes
        store paths to and the upload daemon (`niks3-hook serve`) listens on.
      '';
    };

    maxConcurrentUploads = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = ''
        Maximum concurrent uploads for the auto-upload daemon. Kept low
        because the cache is backed by Backblaze B2, whose API rate limit
        throttles (and historically errored) under high upload concurrency.
      '';
    };

    batchSize = lib.mkOption {
      type = lib.types.int;
      default = 50;
      description = "Number of store paths the daemon collects before pushing a batch.";
    };

    idleExitTimeout = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = ''
        Seconds of idle time before the upload daemon exits; 0 keeps it
        resident. On darwin the daemon is a KeepAlive launchd service that
        owns its socket, so it must stay resident (0). On NixOS the upstream
        module socket-activates the daemon, so a non-zero value is also fine.
      '';
    };

    verifyS3Integrity = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Verify objects actually exist in S3 before skipping re-upload.";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable niks3-hook debug logging.";
    };

    backfillMaxConcurrentUploads = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = ''
        Per-process concurrency for the one-shot niks3-backfill script.
        Combined with NIKS3_BACKFILL_PROCS (default 1) gives effective
        parallelism PROCS*JOBS. Kept below the niks3 server's 5 req/s
        rate limit by default to avoid thrashing on 429s.
      '';
    };

    backfillCheckConcurrency = lib.mkOption {
      type = lib.types.int;
      default = 64;
      description = ''
        Parallel HEAD requests against the CDN cache URL during backfill.
        CF tolerates much higher concurrency than the niks3 API, so this
        defaults far above `backfillMaxConcurrentUploads`. Override at
        runtime via NIKS3_BACKFILL_CHECK_PROCS.
      '';
    };

    authTokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the niks3 auth token";
    };
  };

  # The post-build-hook and upload daemon are wired per-platform (linux.nix
  # delegates to upstream's niks3-auto-upload NixOS module; darwin.nix
  # hand-rolls a launchd daemon, since upstream only ships a systemd unit).
  # Shared here: just the manual backfill tool.
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ scripts.backfillScript ];
  };
}
