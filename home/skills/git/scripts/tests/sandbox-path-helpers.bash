# Shared bats helper: stage this dir's fake binaries (gh, ...) into a
# writable copy with a shebang that actually resolves, then put that copy ahead
# of $PATH — instead of $script_dir itself.
#
# Also stage the skill scripts under test with rewritten shebangs so scripts
# that invoke sibling scripts via "$script_dir/<sibling>.sh" (such as
# merge-onto-default.sh and watch-pr.sh) do not fail with "bad interpreter"
# under the Nix build sandbox.
stage_fakes_and_export_path() {
  local tests_dir="$1"
  local fakes_dir="$BATS_TEST_TMPDIR/fakes"
  mkdir -p "$fakes_dir"
  local f base
  for f in "$tests_dir"/*; do
    [ -f "$f" ] && [ -x "$f" ] || continue
    case "$f" in *.bats) continue ;; esac
    base="$(basename "$f")"
    { printf '#!%s\n' "$(command -v bash)"; tail -n +2 "$f"; } >"$fakes_dir/$base"
    chmod +x "$fakes_dir/$base"
  done
  export PATH="$fakes_dir:$PATH"

  local parent_dir="$tests_dir/.."
  local scripts_dir="$BATS_TEST_TMPDIR/scripts"
  mkdir -p "$scripts_dir"
  for f in "$parent_dir"/*.sh; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    { printf '#!%s\n' "$(command -v bash)"; tail -n +2 "$f"; } >"$scripts_dir/$base"
    chmod +x "$scripts_dir/$base"
  done
  if [ -d "$parent_dir/lib" ]; then
    cp -r "$parent_dir/lib" "$scripts_dir/"
    chmod -R u+w "$scripts_dir/lib"
  fi
  chmod -R u+w "$scripts_dir"
  if [ -n "${script:-}" ] && [ -f "$scripts_dir/$(basename "$script")" ]; then
    script="$scripts_dir/$(basename "$script")"
  fi
}
