# Shared bats helper: stage this dir's fake binaries (curl, llama-server,
# stat, copilot, ...) into a writable copy with a shebang that actually
# resolves, then put that copy ahead of $PATH.
#
# Why: these fakes ship with `#!/usr/bin/env bash` for portability when run
# normally, but the Nix build sandbox has no /usr/bin/env (see
# modules/niks3-cache-push/tests/backfill.bats for the same gotcha), so
# executing them straight from the read-only Nix store fails with "bad
# interpreter". Rewriting the shebang to an absolute, resolved bash path
# before copying to a writable dir fixes that without touching the
# checked-in fakes themselves.
stage_fakes_and_export_path() {
  local script_dir="$1"
  local fakes_dir="$BATS_TEST_TMPDIR/fakes"
  mkdir -p "$fakes_dir"
  local f base
  for f in "$script_dir"/*; do
    [ -f "$f" ] && [ -x "$f" ] || continue
    case "$f" in *.bats) continue ;; esac
    base="$(basename "$f")"
    { printf '#!%s\n' "$(command -v bash)"; tail -n +2 "$f"; } >"$fakes_dir/$base"
    chmod +x "$fakes_dir/$base"
  done
  export PATH="$fakes_dir:$script_dir:$PATH"
}
