#!/usr/bin/env bash
# Container entrypoint for Create: Arkana + Aeronautics server.
#
# /opt/server holds the immutable prepared server tree (mods, configs,
# shaderpacks, NeoForge installer) baked by Nix. Arkana doesn't ship a
# pre-installed server pack the way CSC does, so libraries/ is empty in the
# image and gets populated on the FIRST boot by running the NeoForge
# installer against /data — that puts NeoForge's Maven-fetched jars on the
# PVC where they survive image upgrades and a re-install only re-runs if
# /data/libraries vanishes.
set -euo pipefail

cd /data

# First-boot bootstrap: NeoForge installer downloads ~80 MB of Maven
# artifacts into /data/libraries plus generates run.sh and a placeholder
# user_jvm_args.txt. It needs outbound network — the k8s pod must allow it
# at least once. Subsequent boots skip this step.
if [ ! -d /data/libraries ]; then
  echo "[entrypoint] First boot: running NeoForge installer..."
  java -jar /opt/server/neoforge-installer.jar --installServer /data
  # The installer writes its own user_jvm_args.txt with placeholder flags.
  # Overwrite it with our tuned Aikar's flags every time so a NeoForge
  # version bump doesn't silently revert to vanilla GC tuning.
  cp /opt/server/user_jvm_args.txt /data/user_jvm_args.txt
fi

# Symlink immutable directories from the baked tree into the working dir.
# `defaultconfigs` is optional on NeoForge packs (Arkana ships configs/).
for d in mods kubejs datapacks defaultconfigs; do
  if [ -e "/opt/server/$d" ] && [ ! -e "$d" ]; then
    ln -s "/opt/server/$d" "$d"
  fi
done

# Copy mutable files on first start so admins can edit them in-place on the
# PVC. We deliberately skip user_jvm_args.txt here because the installer-
# stage above already overwrote it.
for f in server.properties eula.txt; do
  if [ ! -e "$f" ] && [ -e "/opt/server/$f" ]; then
    cp "/opt/server/$f" "$f"
  fi
done

# `config/` may be edited by admins (per-mod tuning); copy on first start
# so changes persist on the PVC and survive image upgrades.
if [ ! -e config ] && [ -e /opt/server/config ]; then
  cp -r /opt/server/config config
fi

# Spark profiler's async-profiler engine dlopens libstdc++.so.6 directly.
# dockerTools images have no /lib search path, so point LD_LIBRARY_PATH at
# the libstdc++ store path baked into the image. Without this spark falls
# back to the JVM sampler — works but less precise on native frames.
export LD_LIBRARY_PATH="@libstdcxxLib@${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Heap size (Java -Xmx/-Xms format, e.g. 2560m, 2g). Default 2560m fits a
# 4 GiB pod limit alongside non-heap caps + native overhead.
HEAP="${MINECRAFT_HEAP:-2560m}"

# GC log lives on the PVC so post-mortem analysis survives pod restarts.
mkdir -p logs

# Read JVM tuning flags into an array so each flag is a separate argv entry.
mapfile -t JVM_TUNING < <(grep -v '^[[:space:]]*#' /data/user_jvm_args.txt | grep -v '^[[:space:]]*$')

# NeoForge's unix_args.txt path includes the loader version (e.g.
# `neoforge-21.1.206`) which we don't want to hardcode. Discover it by glob
# so the entrypoint survives a NeoForge bump in the underlying server tree.
shopt -s nullglob
NEOFORGE_ARGS=( /data/libraries/net/neoforged/neoforge/*/unix_args.txt )
if [ ${#NEOFORGE_ARGS[@]} -ne 1 ]; then
  echo "ERROR: expected exactly one NeoForge unix_args.txt under /data/libraries/net/neoforged/neoforge/, found ${#NEOFORGE_ARGS[@]}" >&2
  printf '  %s\n' "${NEOFORGE_ARGS[@]}" >&2
  exit 1
fi

exec java \
  -Xms"$HEAP" -Xmx"$HEAP" \
  -Xlog:gc*:file=logs/gc.log:time,uptime:filecount=5,filesize=10M \
  "${JVM_TUNING[@]}" \
  "@${NEOFORGE_ARGS[0]}" \
  nogui
