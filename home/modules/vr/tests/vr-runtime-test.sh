#!/usr/bin/env bash
# Drives vr-runtime against a throwaway HOME so the real runtime
# configuration is never touched. Usage:
#
#   bash vr-runtime-test.sh /path/to/vr-runtime
set -euo pipefail

VR_RUNTIME="${1:?usage: vr-runtime-test.sh /path/to/vr-runtime}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP"
export VR_RUNTIME_DRY_RUN=1
export VR_RUNTIME_WIVRN_JSON="$TMP/fake-wivrn/openxr_wivrn.json"
export VR_RUNTIME_STEAMVR_ROOT="$TMP/fake-steam/steamapps/common/SteamVR"
export VR_RUNTIME_OPENCOMPOSITE_ROOT="$TMP/fake-opencomposite/lib/opencomposite"
export VR_RUNTIME_STEAM_ROOT="$TMP/fake-steam"

mkdir -p \
  "$(dirname "$VR_RUNTIME_WIVRN_JSON")" \
  "$VR_RUNTIME_STEAMVR_ROOT" \
  "$VR_RUNTIME_OPENCOMPOSITE_ROOT"

cat > "$VR_RUNTIME_WIVRN_JSON" <<'EOF'
{"file_format_version":"1.0.0","runtime":{"name":"Monado","library_path":"/fake/libopenxr_wivrn.so"}}
EOF

cat > "$VR_RUNTIME_STEAMVR_ROOT/steamxr_linux64.json" <<'EOF'
{"file_format_version":"1.0.0","runtime":{"VALVE_runtime_is_steamvr":true,"name":"SteamVR","library_path":"/fake/vrclient.so"}}
EOF

OPENXR="$HOME/.config/openxr/1/active_runtime.json"
OPENVR="$HOME/.config/openvr/openvrpaths.vrpath"

# 1. status on a virgin HOME reports unset rather than crashing
out="$("$VR_RUNTIME" status)" || fail "status exited non-zero on a virgin HOME"
grep -qi "unset" <<<"$out" || fail "status did not report unset: $out"

# 2. switching to steamvr writes both files, SteamVR first in openvrpaths
"$VR_RUNTIME" steamvr >/dev/null || fail "steamvr switch exited non-zero"
grep -q "SteamVR" "$OPENXR" || fail "active_runtime.json does not name SteamVR"
python3 -c "
import json, sys
doc = json.load(open('$OPENVR'))
assert 'SteamVR' in doc['runtime'][0], doc['runtime']
assert len(doc['runtime']) == 2, doc['runtime']
assert doc['jsonid'] == 'vrpathreg', doc
" || fail "openvrpaths.vrpath does not list SteamVR first with OpenComposite second"

# 3. the steamvr manifest is SteamVR's own, not a hand-written stand-in
python3 -c "
import json
doc = json.load(open('$OPENXR'))
assert doc['runtime'].get('VALVE_runtime_is_steamvr') is True, doc
" || fail "active_runtime.json is not SteamVR's own shipped manifest"

# 4. on a virgin file the config and log paths come from the Steam root, not
#    from the runtime path — deriving them from the runtime wrote
#    /nix/store/config on the WiVRn branch, where the runtime is OpenComposite
python3 -c "
import json
doc = json.load(open('$OPENVR'))
assert doc['config'] == ['$TMP/fake-steam/config'], doc['config']
assert doc['log'] == ['$TMP/fake-steam/logs'], doc['log']
" || fail "virgin-file config/log did not fall back to the Steam root"

# 5. a file carrying store paths from the buggy revision self-heals rather
#    than preserving the garbage
python3 - <<PY || fail "could not seed store-path garbage"
import json
q = "$OPENVR"
doc = json.load(open(q))
doc["config"] = ["/nix/store/config"]
doc["log"] = ["/nix/store/logs"]
json.dump(doc, open(q, "w"), indent=3)
PY
"$VR_RUNTIME" steamvr >/dev/null || fail "steamvr switch exited non-zero"
python3 -c "
import json
doc = json.load(open('$OPENVR'))
assert doc['config'] == ['$TMP/fake-steam/config'], doc['config']
assert doc['log'] == ['$TMP/fake-steam/logs'], doc['log']
" || fail "store-path config/log were preserved instead of healed"

# 6. config and log paths survive a switch — the Steam library is on a
#    separate mount on the real host, so they are not derivable from HOME
python3 - <<PY || fail "could not seed config/log paths"
import json
p = "$OPENVR"
doc = json.load(open(p))
doc["config"] = ["/media/elsewhere/Steam/config"]
doc["log"] = ["/media/elsewhere/Steam/logs"]
json.dump(doc, open(p, "w"), indent=3)
PY
"$VR_RUNTIME" wivrn >/dev/null || fail "wivrn switch exited non-zero"
python3 -c "
import json
doc = json.load(open('$OPENVR'))
assert doc['config'] == ['/media/elsewhere/Steam/config'], doc['config']
assert doc['log'] == ['/media/elsewhere/Steam/logs'], doc['log']
" || fail "switching clobbered the existing config/log paths"

# 7. switching to wivrn repoints OpenXR at the wivrn runtime
grep -q "Monado" "$OPENXR" || fail "active_runtime.json does not name Monado"

# 8. the files must be writable, not store symlinks — the whole point
[ -w "$OPENXR" ] || fail "active_runtime.json is not writable; a switcher cannot work"
[ -w "$OPENVR" ] || fail "openvrpaths.vrpath is not writable; a switcher cannot work"

# 9. status reflects the last switch
out="$("$VR_RUNTIME" status)"
grep -qi "wivrn" <<<"$out" || fail "status did not report wivrn: $out"

# 10. an unknown subcommand fails loudly rather than silently doing nothing
if "$VR_RUNTIME" nonsense >/dev/null 2>&1; then
  fail "unknown subcommand exited zero"
fi

echo "PASS: all vr-runtime assertions held"
