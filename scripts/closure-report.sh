#!/usr/bin/env bash
# Generate a closure size report for explicitly installed packages in a NixOS host.
#
# Usage:
#   ./scripts/closure-report.sh <flake-attr> [output-file]
#
# Examples:
#   ./scripts/closure-report.sh .#nixosConfigurations.ali-desktop
#   ./scripts/closure-report.sh .#nixosConfigurations.ali-framework-laptop report.md

set -euo pipefail

FLAKE_ATTR="${1:?Usage: $0 <flake-attr> [output-file]}"
OUTPUT="${2:-/dev/stdout}"
HOST_NAME="${FLAKE_ATTR##*.}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Detect CI for log grouping
if [ "${CI:-}" = "true" ]; then
  log()    { echo "::group::$1" >&2; }
  endlog() { echo "::endgroup::" >&2; }
else
  log()    { echo "--- $1 ---" >&2; }
  endlog() { :; }
fi

EVAL_EXPR='pkgs: map (p: { name = p.name or p.pname or "unknown"; path = builtins.unsafeDiscardStringContext p.outPath; }) pkgs'

# --- Step 1: Evaluate package lists ---
log "Evaluating system packages for ${HOST_NAME}"
nix eval --json "${FLAKE_ATTR}.config.environment.systemPackages" --apply "$EVAL_EXPR" \
  > "$TMPDIR/sys.json" 2>/dev/null
sys_count=$(python3 -c "import json; print(len(json.load(open('$TMPDIR/sys.json'))))")
echo "Found ${sys_count} system packages" >&2
endlog

log "Evaluating home-manager packages for ${HOST_NAME}"
echo "[]" > "$TMPDIR/hm.json"
for user in ali root; do
  if nix eval --json "${FLAKE_ATTR}.config.home-manager.users.${user}.home.packages" \
       --apply "$EVAL_EXPR" > "$TMPDIR/hm.json" 2>/dev/null; then
    break
  fi
done
hm_count=$(python3 -c "import json; print(len(json.load(open('$TMPDIR/hm.json'))))")
echo "Found ${hm_count} home-manager packages" >&2
endlog

# --- Step 2: Extract unique store paths and tag sources ---
python3 <<PYEOF
import json, sys

sys_pkgs = json.load(open("$TMPDIR/sys.json"))
hm_pkgs = json.load(open("$TMPDIR/hm.json"))

combined = {}
for p in sys_pkgs:
    combined[p["path"]] = {"name": p["name"], "source": "system"}
for p in hm_pkgs:
    if p["path"] in combined:
        combined[p["path"]]["source"] = "both"
    else:
        combined[p["path"]] = {"name": p["name"], "source": "home-manager"}

json.dump(combined, open("$TMPDIR/all-pkgs.json", "w"))
print(f"{len(combined)} unique packages", file=sys.stderr)
PYEOF

python3 -c "
import json
pkgs = json.load(open('$TMPDIR/all-pkgs.json'))
for path in pkgs:
    print(path)
" > "$TMPDIR/paths.txt"

path_count=$(wc -l < "$TMPDIR/paths.txt")

# --- Step 3: Realise from cache ---
log "Realising ${path_count} packages from cache"
xargs -n 50 nix-store --realise < "$TMPDIR/paths.txt" >/dev/null 2>&1 || true
endlog

# --- Step 4: Query closure sizes for valid paths ---
log "Querying closure sizes"
: > "$TMPDIR/valid-paths.txt"
while IFS= read -r p; do
  if nix-store --check-validity "$p" 2>/dev/null; then
    echo "$p" >> "$TMPDIR/valid-paths.txt"
  fi
done < "$TMPDIR/paths.txt"

valid_count=$(wc -l < "$TMPDIR/valid-paths.txt")
echo "${valid_count} of ${path_count} paths available in store" >&2

if [ "$valid_count" -eq 0 ]; then
  echo "Error: no paths could be realised — check cache configuration" >&2
  exit 1
fi

xargs nix path-info --closure-size < "$TMPDIR/valid-paths.txt" > "$TMPDIR/sizes.txt" 2>/dev/null
endlog

# --- Step 5: Generate report ---
log "Generating report"
python3 - "$HOST_NAME" "$OUTPUT" "$TMPDIR/all-pkgs.json" "$TMPDIR/sizes.txt" <<'PYEOF'
import json, re, sys

host = sys.argv[1]
output_path = sys.argv[2]
pkgs_file = sys.argv[3]
sizes_file = sys.argv[4]

def human_size(b):
    for u in ['B', 'KiB', 'MiB', 'GiB']:
        if abs(b) < 1024.0:
            return f"{b:.1f} {u}"
        b /= 1024.0
    return f"{b:.1f} TiB"

# Load package metadata
pkg_meta = json.load(open(pkgs_file))

# Parse closure sizes
sizes = {}
with open(sizes_file) as f:
    for line in f:
        parts = line.strip().split('\t')
        if len(parts) >= 2:
            path = parts[0].strip()
            size = int(parts[1].strip())
            sizes[path] = size

# Build combined list
results = []
meta_names = {'system-path', 'home-manager-path', 'home-manager-generation',
              'home-manager-files', 'user-environment'}

for path, meta in pkg_meta.items():
    if path not in sizes:
        continue
    name = meta['name']
    if any(m in name for m in meta_names):
        continue
    results.append({
        'name': name,
        'size': sizes[path],
        'source': meta['source'],
    })

results.sort(key=lambda x: x['size'], reverse=True)

out = open(output_path, 'w') if output_path != '/dev/stdout' else sys.stdout

out.write(f"# Closure Size Report: {host}\n\n")
out.write(f"**Packages analysed**: {len(results)}\n\n")
out.write("| # | Package | Closure Size | Source |\n")
out.write("|---|---------|-------------|--------|\n")
for i, r in enumerate(results, 1):
    out.write(f"| {i} | {r['name']} | {human_size(r['size'])} | {r['source']} |\n")

if output_path != '/dev/stdout':
    out.close()
    print(f"Report written to {output_path} ({len(results)} packages)", file=sys.stderr)
PYEOF

endlog
