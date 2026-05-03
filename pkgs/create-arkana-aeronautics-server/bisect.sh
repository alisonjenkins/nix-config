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

# Always start from a clean PVC so the NeoForge installer re-runs and
# stale mod state from a prior iteration doesn't mask the new mod set.
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run --rm -v "$DATA:/data" alpine sh -c 'rm -rf /data/* /data/.[!.]*' >/dev/null 2>&1
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

# Stream logs and watch for terminal markers. SIGPIPE on grep -m1 ends the
# pipeline so we get a single hit and stop tailing.
docker logs -f "$CONTAINER" > "$LOG" 2>&1 &
log_pid=$!
trap 'kill $log_pid 2>/dev/null || true; docker stop "$CONTAINER" >/dev/null 2>&1 || true' EXIT

start=$(date +%s)
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
  sleep 2
done

if [ -z "$result" ]; then
  echo "[bisect] TIMEOUT after ${TIMEOUT}s — no Done/FATAL marker"
  result=timeout
fi

case "$result" in
  ok)
    grep -E 'Done \([0-9.]+s\)! For help' "$LOG" | tail -1
    echo "[bisect] PASS"
    exit 0
    ;;
  fail|timeout)
    echo "[bisect] FAIL — last 3 mod-loading exception bullets:"
    docker run --rm -v "$DATA:/data" alpine sh -c '
      ls /data/crash-reports/ 2>/dev/null | tail -1 | xargs -I{} cat /data/crash-reports/{}
    ' 2>/dev/null | grep -E '(Mod file:|Failure message:|Exception message:)' | head -9
    echo "[bisect] full log: $LOG"
    exit 1
    ;;
esac
