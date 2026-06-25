{ pkgs, lib, cfg, niks3 }:
{
  # One-shot backfill of the entire local store into the cache. Independent
  # of the auto-upload daemon (which only handles paths built after it is
  # running) — this walks every store path, HEAD-checks the CDN to skip
  # already-cached narinfos, and `niks3 push`es the rest. Run manually as
  # root (it reads the auth token).
  backfillScript = pkgs.writeShellApplication {
    name = "niks3-backfill";
    runtimeInputs = [ niks3 pkgs.nix pkgs.curl pkgs.coreutils ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "Must run as root (needs to read ${toString cfg.authTokenFile})." >&2
        exit 1
      fi

      export CACHE_URL=${lib.escapeShellArg cfg.cacheUrl}
      export SERVER_URL=${lib.escapeShellArg cfg.serverUrl}
      export AUTH_TOKEN_FILE=${lib.escapeShellArg (toString cfg.authTokenFile)}
      : "''${NIKS3_BACKFILL_CHECK_PROCS:=${toString cfg.backfillCheckConcurrency}}"
      : "''${NIKS3_BACKFILL_PROCS:=1}"
      : "''${NIKS3_BACKFILL_JOBS:=${toString cfg.backfillMaxConcurrentUploads}}"
      : "''${NIKS3_BACKFILL_BATCH:=500}"
      export NIKS3_BACKFILL_CHECK_PROCS NIKS3_BACKFILL_PROCS NIKS3_BACKFILL_JOBS NIKS3_BACKFILL_BATCH

      ${builtins.readFile ./backfill.sh}

      run_backfill
    '';
  };
}
