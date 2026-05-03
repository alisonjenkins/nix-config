#!/usr/bin/env bash
# Build, deploy, and smoke-test the Arkana+Aeronautics server image with a
# specific set of Arkana groups enabled. Used to bisect which groups
# co-exist with the bumped Create 6.0.10 / NeoForge 21.1.228 base.
#
# Usage:
#   bisect.sh                              # floor only (no Arkana groups)
#   bisect.sh core-libs                    # floor + core-libs group
#   bisect.sh core-libs apothic letsdo     # union of those groups
#
# Exit code:
#   0  — server reached "Done (Xs)! For help"
#   1  — server crashed (FATAL / mod-load failure / OOM / Minecraft Main died)
#   2  — script error (build, docker, …)
#
# Side effects:
#   - Wipes /tmp/arkana-data so each run starts from a fresh PVC.
#   - Removes any pre-existing `arkana-smoke` container.
#   - Builds .#packages.aarch64-linux.minecraft-arkana-aeronautics-image
#     with the requested groups via `--arg enabledArkanaGroups [...]`.
#   - Loads + runs the image, streams logs to /tmp/arkana-bisect.log.
#
# This script does NOT call `docker system prune` — only its own container
# is removed. Old dangling images from prior iterations should be cleaned
# manually with `docker image prune -f` (idempotent, only nukes untagged).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG=/tmp/arkana-bisect.log
DATA=/tmp/arkana-data
CONTAINER=arkana-smoke
IMAGE_TAG=v1.5-aeronautics-1.2.1
IMAGE_NAME=create-arkana-aeronautics-server

# Boot timeout in seconds. The Aeronautics floor reaches "Done" in ~23 s on
# colima/aarch64-linux; cold-boot of the full Arkana set has historically
# crashed inside ~2 min. 5 min is a generous upper bound — bisect halts on
# explicit FATAL/Failed lines anyway.
TIMEOUT=${TIMEOUT:-300}

# Render the requested groups as a Nix list literal. Empty input → "[ ]".
groups_arg=""
for g in "$@"; do
  groups_arg+=" \"$g\""
done

flake_attr=".#packages.aarch64-linux.minecraft-arkana-aeronautics-image"

echo "[bisect] enabledArkanaGroups = [${groups_arg} ]"
echo "[bisect] building $flake_attr ..."
# We override only the server pkg's enabledArkanaGroups; the image wraps
# the server pkg with that override propagated.
build_out="$(
  nix build --no-link --print-out-paths --max-jobs 8 \
    --impure \
    --expr "
      let
        flake = builtins.getFlake \"$REPO_ROOT\";
        sys = \"aarch64-linux\";
        pkgs = import flake.inputs.nixpkgs {
          system = sys;
          config.allowUnfree = true;
          overlays = builtins.attrValues flake.outputs.overlays;
        };
        server = pkgs.create-arkana-aeronautics-server.override {
          enabledArkanaGroups = [${groups_arg} ];
        };
        jre = pkgs.temurin-jre-bin-21;
      in pkgs.dockerTools.buildLayeredImage {
        name = \"$IMAGE_NAME\";
        tag = \"$IMAGE_TAG\";
        created = \"1970-01-01T00:00:01Z\";
        contents = [
          pkgs.bashInteractive pkgs.coreutils pkgs.gnugrep pkgs.gawk
          pkgs.cacert pkgs.stdenv.cc.cc.lib jre server
        ];
        maxLayers = 100;
        extraCommands = ''
          mkdir -p opt data tmp
          ln -s \${server} opt/server
          chmod 1777 tmp
        '';
        config = {
          Entrypoint = [ \"\${server}/entrypoint.sh\" ];
          WorkingDir = \"/data\";
          ExposedPorts = { \"25565/tcp\" = { }; };
          Volumes = { \"/data\" = { }; };
          Env = [
            \"JAVA_HOME=\${jre}\"
            \"PATH=\${jre}/bin:/bin\"
            \"MINECRAFT_HEAP=2560m\"
          ];
        };
      }
    " \
    2>&1 | tail -1
)" || { echo "[bisect] nix build failed"; exit 2; }

echo "[bisect] built: $build_out"

# Wipe everything that depends on the mod set, but keep
# /data/libraries (NeoForge's Maven cache from the installer — ~80MB,
# unchanged unless NeoForge version bumps). Saves ~60-90s per round.
# Set FRESH=1 to force a full wipe (use after a NeoForge bump).
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
if [ "${FRESH:-0}" = "1" ]; then
  docker run --rm -v "$DATA:/data" alpine sh -c 'rm -rf /data/* /data/.[!.]*' >/dev/null 2>&1
else
  docker run --rm -v "$DATA:/data" alpine sh -c '
    cd /data
    rm -rf world world_nether world_the_end logs crash-reports config mods kubejs datapacks defaultconfigs run.sh run.bat user_jvm_args.txt server.properties eula.txt 2>/dev/null
  ' >/dev/null 2>&1
fi
mkdir -p "$DATA"

echo "[bisect] loading image..."
docker load < "$build_out" | tail -1

echo "[bisect] starting container..."
docker run -d \
  --name "$CONTAINER" \
  --memory 5g --cpus 4 \
  -v "$DATA:/data" \
  -p 25565:25565 \
  "$IMAGE_NAME:$IMAGE_TAG" >/dev/null

# Stream logs to file. We tail for terminal markers AND emit a phase
# heartbeat every 15s so a watcher can tell what's happening without
# scraping the log themselves.
docker logs -f "$CONTAINER" > "$LOG" 2>&1 &
log_pid=$!
trap 'kill $log_pid 2>/dev/null || true; docker stop "$CONTAINER" >/dev/null 2>&1 || true' EXIT

# Map a regex on the log tail to a human-readable phase label. Order
# matters — later phases override earlier ones when both have matched.
phase_for() {
  local log="$1" phase="boot-pending"
  grep -qE '\[entrypoint\] First boot: running NeoForge installer' "$log"     && phase="installer"
  grep -qE 'Patching environment|Loading [0-9]+ mods'                "$log"   && phase="mod-load"
  grep -qE 'Mod Construction|MOD LOADING'                            "$log"   && phase="mod-construction"
  grep -qE 'Registry initialization|Registry init|RegisterEvent'     "$log"   && phase="registry-init"
  grep -qE 'FMLCommonSetupEvent'                                     "$log"   && phase="common-setup"
  grep -qE 'Preparing start region|Preparing spawn area'             "$log"   && phase="worldgen"
  grep -qE 'Starting net\.minecraft\.server'                         "$log"   && phase="server-start"
  echo "$phase"
}

start=$(date +%s)
last_phase=""
last_status=$start
result=""
while [ "$(($(date +%s) - start))" -lt "$TIMEOUT" ]; do
  if grep -qE 'Done \([0-9.]+s\)! For help' "$LOG"; then
    result=ok
    break
  fi
  if grep -qE '(Failed to start the minecraft|Mod Loading has failed|errors found|OutOfMemoryError|Crash report saved)' "$LOG"; then
    result=fail
    break
  fi

  now=$(date +%s)
  elapsed=$(( now - start ))
  phase=$(phase_for "$LOG")

  # Phase transition → always print.
  if [ "$phase" != "$last_phase" ]; then
    printf '[bisect] [t+%3ds] phase: %s\n' "$elapsed" "$phase"
    last_phase=$phase
    last_status=$now
  # Heartbeat every 15 s so a watcher knows we're not stuck.
  elif [ "$(( now - last_status ))" -ge 15 ]; then
    log_lines=$(wc -l < "$LOG" | tr -d ' ')
    mem=$(docker stats "$CONTAINER" --no-stream --format '{{.MemUsage}}' 2>/dev/null | awk -F/ '{gsub(/^ +| +$/, "", $1); print $1}')
    cpu=$(docker stats "$CONTAINER" --no-stream --format '{{.CPUPerc}}' 2>/dev/null)
    printf '[bisect] [t+%3ds] still %s — %d log lines, mem %s, cpu %s\n' \
      "$elapsed" "$phase" "$log_lines" "$mem" "$cpu"
    last_status=$now
  fi
  sleep 2
done

if [ -z "$result" ]; then
  echo "[bisect] [t+${TIMEOUT}s] TIMEOUT — no Done/FATAL marker"
  echo "[bisect] last 5 log lines:"
  tail -5 "$LOG" | sed 's/^/  /'
  result=timeout
fi

case "$result" in
  ok)
    done_line=$(grep -E 'Done \([0-9.]+s\)! For help' "$LOG" | tail -1)
    echo "[bisect] $done_line"
    echo "[bisect] PASS"
    exit 0
    ;;
  fail|timeout)
    elapsed=$(( $(date +%s) - start ))
    echo "[bisect] [t+${elapsed}s] FAIL"
    # FATAL lines from the log — show all per-mod failures so the
    # watcher sees the full cascade, not just `head -9` of a crash report.
    fatal_lines=$(grep -cE '(FATAL\]|Failed to load correctly|Mod Loading has failed)' "$LOG")
    echo "[bisect] $fatal_lines FATAL/load-failure markers in log"
    echo "[bisect] last crash report (first 9 mod-failure bullets):"
    docker run --rm -v "$DATA:/data" alpine sh -c '
      ls /data/crash-reports/ 2>/dev/null | tail -1 | xargs -I{} cat /data/crash-reports/{}
    ' 2>/dev/null | grep -E '(Mod file:|Failure message:|Exception message:)' | head -9 | sed 's/^/  /'
    echo "[bisect] full log: $LOG"
    exit 1
    ;;
esac
