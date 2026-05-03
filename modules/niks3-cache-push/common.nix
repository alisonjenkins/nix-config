{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.modules.niks3CachePush;
  niks3 = inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.default;
  scripts = import ./scripts.nix { inherit pkgs lib cfg niks3; };
in
{
  options.modules.niks3CachePush = {
    enable = lib.mkEnableOption "queue-based niks3 binary cache push";

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

    maxConcurrentUploads = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Maximum number of concurrent uploads to the cache server (per-build drain).";
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

  config = lib.mkIf cfg.enable {
    nix.settings.post-build-hook = scripts.postBuildHook;
    environment.systemPackages = [ scripts.backfillScript ];
  };
}
