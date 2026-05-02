{ pkgs, lib, cfg, niks3 }:
rec {
  queueDir = "/var/lib/niks3-queue";
  queueFile = "${queueDir}/queue";
  processingFile = "${queueDir}/processing";

  postBuildHook = pkgs.writeShellScript "niks3-queue-hook" ''
    set -euf
    echo "$OUT_PATHS" >> ${queueFile}
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
    runtimeInputs = [ niks3 pkgs.nix ];
    text = ''
      set -euo pipefail
      if [ "$(id -u)" -ne 0 ]; then
        echo "Must run as root (needs to read ${cfg.authTokenFile})." >&2
        exit 1
      fi
      AUTH_TOKEN="$(cat "${cfg.authTokenFile}")"
      : "''${NIKS3_BACKFILL_PROCS:=4}"
      : "''${NIKS3_BACKFILL_JOBS:=${toString cfg.backfillMaxConcurrentUploads}}"
      : "''${NIKS3_BACKFILL_BATCH:=200}"

      echo "Enumerating local store paths..." >&2
      TMP=$(mktemp)
      trap 'rm -f "$TMP"' EXIT
      nix path-info --all | grep -v '\.drv$' > "$TMP"
      TOTAL=$(wc -l < "$TMP")
      echo "Pushing $TOTAL paths with $NIKS3_BACKFILL_PROCS workers x $NIKS3_BACKFILL_JOBS uploads each..." >&2

      < "$TMP" xargs -r -n "$NIKS3_BACKFILL_BATCH" -P "$NIKS3_BACKFILL_PROCS" \
        niks3 push \
          --server-url "${cfg.serverUrl}" \
          --max-concurrent-uploads "$NIKS3_BACKFILL_JOBS" \
          --auth-token "$AUTH_TOKEN"
    '';
  };
}
