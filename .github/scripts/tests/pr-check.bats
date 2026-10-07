#!/usr/bin/env bats
# Tests for .github/scripts/pr-check-x86_64-linux.sh: the parallel section
# runner and the batched-eval fallback. `nix` and `git` are stubs on PATH;
# STUB_* variables choose how they misbehave.
#
# Run from repo root:
#   nix run nixpkgs#bats -- .github/scripts/tests/pr-check.bats

SCRIPT="${BATS_TEST_DIRNAME}/../pr-check-x86_64-linux.sh"

setup() {
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/bin" "$WORK/.github/scripts"
  cp "$SCRIPT" "$WORK/.github/scripts/pr-check-x86_64-linux.sh"
  for helper in check-forgecdn-paths.sh check-skill-frontmatter.sh; do
    printf '#!%s\nexit 0\n' "$BASH" >"$WORK/.github/scripts/$helper"
    chmod +x "$WORK/.github/scripts/$helper"
  done
  write_git_stub
  write_nix_stub
  export PATH="$WORK/bin:$PATH"
  export WORK
  cd "$WORK"
}

teardown() {
  # Lets a stub still waiting on it exit, so a failed test leaves nothing spinning.
  touch "$WORK/release"
  if [ -n "${SCRIPT_PID:-}" ]; then kill "$SCRIPT_PID" 2>/dev/null || true; fi
  if [ -f "$WORK/hang.pid" ]; then kill "$(cat "$WORK/hang.pid")" 2>/dev/null || true; fi
  cd /
  rm -rf "$WORK"
}

write_git_stub() {
  cat >"$WORK/bin/git" <<EOF
#!$BASH
exit 0
EOF
  chmod +x "$WORK/bin/git"
}

write_nix_stub() {
  cat >"$WORK/bin/nix" <<EOF
#!$BASH
args="\$*"
case "\$args" in
  *"--apply builtins.attrNames"*)
    case "\$args" in
      *devShells*) echo '["shell"]' ;;
      *packages*) echo '["good","bad"]' ;;
      *) echo '["m"]' ;;
    esac ;;
  *"builtins.filter"*) echo '["host1"]' ;;
  *deepSeq*)
    if [ -n "\${STUB_BATCH_FAIL:-}" ]; then exit 1; fi
    case "\$args" in
      *nixosConfigurations*)
        if [ -n "\${STUB_HOSTS_WAIT:-}" ]; then
          until [ -e "\$WORK/release" ]; do sleep 0.1; done
        fi ;;
      *packages*)
        if [ -n "\${STUB_HANG_PACKAGES:-}" ]; then
          echo \$\$ >"\$WORK/hang.pid"
          exec sleep 300
        fi ;;
    esac
    echo ok ;;
  *".bad.drvPath"*) echo "error: bad does not evaluate" >&2; exit 1 ;;
  "build "*delegation-bats*)
    if [ -n "\${STUB_KILL_SECTION:-}" ]; then kill -9 \$PPID; fi ;;
  "shell "*)
    shift
    while [ "\$1" != "--command" ]; do shift; done
    shift
    exec "\$@" ;;
  *) echo ok ;;
esac
EOF
  chmod +x "$WORK/bin/nix"
}

@test "passes and batches each set when every eval succeeds" {
  run bash .github/scripts/pr-check-x86_64-linux.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: .#packages.x86_64-linux (2 entries, batched)"* ]]
  [[ "$output" == *"ok: aarch64-linux nixosConfigurations (1 hosts, batched)"* ]]
  [[ "$output" != *"FAILED"* ]]
}

@test "a failed batch falls back to per-entry evals and names the broken one" {
  export STUB_BATCH_FAIL=1
  run bash .github/scripts/pr-check-x86_64-linux.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"ok: .#packages.x86_64-linux.good"* ]]
  [[ "$output" == *"FAILED: .#packages.x86_64-linux.bad"* ]]
  [[ "$output" == *"error: bad does not evaluate"* ]]
}

@test "a section killed before it reports is FAILED, not waited on forever" {
  export STUB_KILL_SECTION=1
  run timeout 60 bash .github/scripts/pr-check-x86_64-linux.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"delegation script tests (bats): FAILED"* ]]
  [[ "$output" == *"hetzner-volume-verify script tests (bats): ok"* ]]
}

@test "a finished section prints while a slower one is still running" {
  export STUB_HOSTS_WAIT=1
  bash .github/scripts/pr-check-x86_64-linux.sh >"$WORK/out.log" 2>&1 &
  SCRIPT_PID=$!
  # The hosts section blocks until $WORK/release exists, so it is still
  # running for as long as we wait here, however slow the other sections are.
  for _ in $(seq 1 300); do
    if grep -q "CurseForge CDN paths, skill frontmatter: ok" "$WORK/out.log"; then break; fi
    sleep 0.1
  done
  grep -q "CurseForge CDN paths, skill frontmatter: ok" "$WORK/out.log"
  kill -0 "$SCRIPT_PID"
  ! grep -q "aarch64-linux nixosConfigurations (evaluated): " "$WORK/out.log"
  touch "$WORK/release"
  wait "$SCRIPT_PID"
  SCRIPT_PID=
  grep -q "aarch64-linux nixosConfigurations (evaluated): ok" "$WORK/out.log"
}

@test "cancelling the script also stops the nix clients under its sections" {
  export STUB_HANG_PACKAGES=1
  bash .github/scripts/pr-check-x86_64-linux.sh >"$WORK/out.log" 2>&1 &
  SCRIPT_PID=$!
  for _ in $(seq 1 50); do
    if [ -s "$WORK/hang.pid" ]; then break; fi
    sleep 0.1
  done
  hung="$(cat "$WORK/hang.pid")"
  kill -0 "$hung"
  kill -TERM "$SCRIPT_PID"
  wait "$SCRIPT_PID" || true
  SCRIPT_PID=
  for _ in $(seq 1 30); do
    if ! kill -0 "$hung" 2>/dev/null; then break; fi
    sleep 0.1
  done
  ! kill -0 "$hung" 2>/dev/null
}
