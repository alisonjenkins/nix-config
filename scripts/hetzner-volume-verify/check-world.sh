#!/usr/bin/env bash
# Prove every chunk of a Minecraft world's region files is readable (spec FR-018).
# Walks every directory named region under WORLD_DIR (overworld, DIM-1, DIM1, 1.21 dimensions/<ns>/<name>),
# ignoring entities and poi, and decodes each chunk of each .mca file down to a valid NBT root compound.
# Prints one `unreadable file=... chunk=X,Z reason=... abs=AX,AZ` line per bad chunk (X,Z are within the region
# file, abs are world chunk coordinates), then `<timestamp> chunks_read=N unreadable=M files=F`.
# Exit 0: nothing unreadable and at least one chunk read. Exit 1: otherwise. Exit 2: usage error.
# Read-only. CHECK_WORLD_JOBS sets the worker count (default: one per CPU).
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: check-world.sh WORLD_DIR" >&2
  exit 2
fi
world=$1
if [ ! -d "$world" ]; then
  echo "check-world: WORLD_DIR is not a directory: $world" >&2
  exit 2
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec python3 "$here/check-world.py" "$world"
