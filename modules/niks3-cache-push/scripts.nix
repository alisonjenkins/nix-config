{ pkgs, lib, cfg, niks3 }:
rec {
  queueDir = "/var/lib/niks3-queue";
  queueFile = "${queueDir}/queue";
  processingFile = "${queueDir}/processing";

  postBuildHook = pkgs.writeShellScript "niks3-queue-hook" ''
    # Best-effort: never fail a build because we couldn't queue.
    mkdir -p ${queueDir} 2>/dev/null || exit 0
    printf '%s\n' "$OUT_PATHS" >> ${queueFile} 2>/dev/null || exit 0
    exit 0
  '';

  drainScript = pkgs.writeShellScript "niks3-drain" ''
    set -euf
    QUEUE=${queueFile}
    PROCESSING=${processingFile}

    mv "$QUEUE" "$PROCESSING" 2>/dev/null || exit 0

    AUTH_TOKEN="$(cat "${cfg.authTokenFile}")"

    cat "$PROCESSING" | xargs -r ${lib.getExe' niks3 "niks3"} push \
      --server-url "${cfg.serverUrl}" \
      --max-concurrent-uploads ${toString cfg.maxConcurrentUploads} \
      --auth-token "$AUTH_TOKEN"

    rm -f "$PROCESSING"
  '';

  backfillScript = pkgs.writeShellApplication {
    name = "niks3-backfill";
    runtimeInputs = [ niks3 pkgs.nix pkgs.curl pkgs.coreutils ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "Must run as root (needs to read ${cfg.authTokenFile})." >&2
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
