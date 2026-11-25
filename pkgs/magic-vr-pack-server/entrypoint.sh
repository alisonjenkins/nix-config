#!/usr/bin/env bash
# Container entrypoint for the magic-vr-pack server.
#
# /opt/server is the immutable server tree baked by Nix (mods, configs,
# NeoForge installer). /data is the persistent volume. The NeoForge installer
# runs once on first boot to populate /data/libraries, because the Nix sandbox
# blocks its Maven downloads at build time.
set -euo pipefail

cd /data

# The marker is written only after a successful install, so an interrupted
# first boot retries; it holds the version, so a NeoForge bump reinstalls.
NEOFORGE_VERSION=@neoforgeVersion@
INSTALL_MARKER=/data/.neoforge-installed
if [ "$(cat "$INSTALL_MARKER" 2>/dev/null || true)" != "$NEOFORGE_VERSION" ]; then
  echo "[entrypoint] Running NeoForge $NEOFORGE_VERSION installer..."
  java -jar /opt/server/neoforge-installer.jar --installServer /data
  printf '%s\n' "$NEOFORGE_VERSION" >"$INSTALL_MARKER"
fi

# JVM flags are image-owned (they carry the CVE-2026-114938 mitigation), so
# they are re-synced every boot rather than left editable on the volume.
cp -f /opt/server/user_jvm_args.txt /data/user_jvm_args.txt

for d in mods defaultconfigs; do
  if [ -e "/opt/server/$d" ] && [ ! -e "$d" ]; then
    ln -s "/opt/server/$d" "$d"
  fi
done

for f in server.properties eula.txt; do
  if [ ! -e "$f" ] && [ -e "/opt/server/$f" ]; then
    cp "/opt/server/$f" "$f"
    chmod 644 "$f"
  fi
done

# shellcheck source=rcon.sh
source "${BASH_SOURCE[0]%/*}/rcon.sh"
configure_rcon /data/server.properties

# config/ is admin-tunable: seed it once, then leave it on the volume.
if [ ! -e config ] && [ -e /opt/server/config ]; then
  cp -r /opt/server/config config
  chmod -R u+w config
fi

# Image-owned, overwritten every boot. fml.toml must keep
# disableConfigWatcher=true (inotify budget with ~150 mods);
# neovelocity-common.toml must keep reading the mounted forwarding secret.
for f in fml.toml neovelocity-common.toml l2configs/l2hostility-server.toml; do
  mkdir -p "config/${f%/*}"
  cp -f "/opt/server/config/$f" "config/$f"
done

# The quest book is pack-owned too: a stale copy on the volume once held an
# entity id FTB Quests cannot parse and kicked every player on join.
# Player progress lives in the world save, not here.
rm -rf config/ftbquests
cp -r /opt/server/config/ftbquests config/ftbquests
chmod -R u+w config/ftbquests

# NeoVelocity reads the proxy's shared secret from /data/forwarding.secret,
# mounted from a k8s Secret. Without it no player can log in.
if [ ! -s /data/forwarding.secret ]; then
  echo "[entrypoint] WARNING: /data/forwarding.secret missing or empty; proxy logins will fail" >&2
fi

# spark's async-profiler dlopens libstdc++; dockerTools images have no /lib.
export LD_LIBRARY_PATH="@libstdcxxLib@${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Java -Xmx format (e.g. 9g, 10240m). Pod limit = heap + ~2.5 GiB.
HEAP="${MINECRAFT_HEAP:-9g}"

mkdir -p logs

mapfile -t JVM_TUNING < <(grep -v '^[[:space:]]*#' /data/user_jvm_args.txt | grep -v '^[[:space:]]*$')

NEOFORGE_ARGS="/data/libraries/net/neoforged/neoforge/$NEOFORGE_VERSION/unix_args.txt"
if [ ! -f "$NEOFORGE_ARGS" ]; then
  echo "ERROR: $NEOFORGE_ARGS is missing; delete $INSTALL_MARKER to rerun the installer" >&2
  exit 1
fi

exec java \
  -Xms"$HEAP" -Xmx"$HEAP" \
  -Xlog:gc*:file=logs/gc.log:time,uptime:filecount=5,filesize=10M \
  "${JVM_TUNING[@]}" \
  "@$NEOFORGE_ARGS" \
  nogui
