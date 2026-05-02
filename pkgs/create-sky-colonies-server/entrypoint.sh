#!/usr/bin/env bash
# Container entrypoint for Create Sky Colonies server.
# /opt/server holds the immutable prepared server tree (mods, libraries, configs).
# /data is the writable PVC where world data, logs, and user-edited configs live.
set -euo pipefail

cd /data

# Symlink immutable directories from the baked tree into the working dir.
# These never need editing at runtime.
for d in libraries mods defaultconfigs kubejs datapacks; do
  if [ ! -e "$d" ]; then
    ln -s "/opt/server/$d" "$d"
  fi
done

# Copy mutable files on first start so admins can edit them in-place on the PVC.
for f in server.properties eula.txt user_jvm_args.txt; do
  if [ ! -e "$f" ]; then
    cp "/opt/server/$f" "$f"
  fi
done

# `config/` may be edited by admins (per-mod tuning); copy on first start
# so changes persist on the PVC and survive image upgrades.
if [ ! -e config ]; then
  cp -r /opt/server/config config
fi

# Spark profiler's async-profiler engine dlopens libstdc++.so.6 directly.
# dockerTools images have no /lib search path, so point LD_LIBRARY_PATH at
# the libstdc++ store path baked into the image. Without this spark falls
# back to the JVM sampler — works but less precise on native frames.
export LD_LIBRARY_PATH="@libstdcxxLib@${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Heap size (Java -Xmx/-Xms format, e.g. 2560m, 2g). Default 2g fits a
# 4 GiB pod limit alongside non-heap caps + native overhead.
HEAP="${MINECRAFT_HEAP:-2g}"

# GC log lives on the PVC so post-mortem analysis survives pod restarts.
mkdir -p logs

# Read JVM tuning flags into an array so each flag is a separate argv entry.
mapfile -t JVM_TUNING < <(grep -v '^[[:space:]]*#' /opt/server/user_jvm_args.txt | grep -v '^[[:space:]]*$')

exec java \
  -Xms"$HEAP" -Xmx"$HEAP" \
  -Xlog:gc*:file=logs/gc.log:time,uptime:filecount=5,filesize=10M \
  "${JVM_TUNING[@]}" \
  @libraries/net/minecraftforge/forge/1.20.1-47.4.12/unix_args.txt \
  nogui
