#!/usr/bin/env bash
set -euo pipefail

# git exports these while a commit hook runs; they would point the test repos at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

script="$(cd "$(dirname "$0")" && pwd)/build.sh"
real_git="$(command -v git)"
export REAL_GIT="$real_git"
export REAL_NIX
REAL_NIX="$(command -v nix)"
tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_TERMINAL_PROMPT=0

mkdir "$tmp/bin"
cat > "$tmp/bin/nix" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" = eval ]]; then
  printf '%s\n' "$@" > "$TARGET_LOG"
  if [[ "${REAL_PROFILE_SELECTION:-0}" -eq 1 ]]; then exec "$REAL_NIX" "$@"; fi
  printf '"%s"\n' "${TEST_TARGET:-nixosConfigurations.Test-Mac.config.system.build.toplevel}"
  exit "${TARGET_STATUS:-0}"
fi
printf '%s\n' "$@" > "$BUILD_LOG"
echo "fake build stdout"
echo "fake build stderr" >&2
if [[ "${BUILD_STATUS:-0}" -eq 0 ]]; then ln -sf "$BUILD_LOG" result; fi
exit "${BUILD_STATUS:-0}"
EOF
cat > "$tmp/bin/osascript" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$NOTIFICATION_LOG"
exit "${NOTIFICATION_STATUS:-0}"
EOF
cat > "$tmp/bin/hostname" <<'EOF'
#!/usr/bin/env bash
echo Test-Mac
EOF
cat > "$tmp/bin/id" <<'EOF'
#!/usr/bin/env bash
echo TestUser
EOF
cat > "$tmp/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify-send\n%s\n' "$@" >> "$NOTIFICATION_LOG"
exit "${NOTIFICATION_STATUS:-0}"
EOF
cat > "$tmp/bin/uname" <<'EOF'
#!/usr/bin/env bash
echo "${TEST_PLATFORM:-Darwin}"
EOF
cat > "$tmp/bin/git" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAIL_MERGE:-0}" -eq 1 && "$1" = merge ]]; then exit 17; fi
if [[ "${FAIL_DROP:-0}" -eq 1 && "$1" = stash && "${2:-}" = drop ]]; then exit 18; fi
exec "$REAL_GIT" "$@"
EOF
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"

fail() { echo "FAIL: $*" >&2; exit 1; }

setup() {
  local name="$1"
  mkdir "$tmp/$name"
  git init -q --bare --initial-branch=main "$tmp/$name/origin"
  git clone -q "$tmp/$name/origin" "$tmp/$name/upstream"
  (
    cd "$tmp/$name/upstream"
    cat > flake.nix <<'EOF'
{
  outputs = { self }: {
    nixosConfigurations.Test-Mac = {};
    homeConfigurations = {
      "TestUser@Test-Mac" = {};
      Test-Mac = {};
      TestUser = {};
    };
  };
}
EOF
    printf 'result\nignored\n' > .gitignore
    echo initial > tracked
    git add .
    git -c commit.gpgsign=false commit -qm initial
    git push -q
  )
  git clone -q "$tmp/$name/origin" "$tmp/$name/repo"
  repository="$tmp/$name/repo"
  export BUILD_LOG="$tmp/$name/build.log" NOTIFICATION_LOG="$tmp/$name/notifications.log"
  export TARGET_LOG="$tmp/$name/target.log"
  export BUILD_STATUS=0
  export NOTIFICATION_STATUS=0 FAIL_MERGE=0 FAIL_DROP=0 TEST_PLATFORM=Darwin
  export TARGET_STATUS=0 TEST_TARGET=nixosConfigurations.Test-Mac.config.system.build.toplevel
  export REAL_PROFILE_SELECTION=0
  export XDG_STATE_HOME="$tmp/$name/state"
}

advance() {
  (
    cd "$tmp/$1/upstream"
    echo upstream > "$2"
    git add .
    git -c commit.gpgsign=false commit -qm update
    git push -q
  )
}

run() {
  (
    cd "${RUN_DIR:-$tmp}"
    bash -c 'configured_repository="$1"; expected_origin="$2"; script="$3"; shift 3; source "$script"' \
      bash "${CONFIGURED-$repository}" "${EXPECTED_ORIGIN-$(dirname "$repository")/origin}" "$script" "$@"
  ) > "$tmp/output" 2>&1
}

setup success
echo old > "$repository/tracked"
git -C "$repository" stash push -qm previous
old_stash="$(git -C "$repository" rev-parse refs/stash)"
echo staged > "$repository/tracked"
git -C "$repository" add tracked
echo unstaged >> "$repository/tracked"
echo untracked > "$repository/local"
echo private > "$repository/ignored"
before="$(git -C "$repository" status --porcelain)"
advance success new-file
run || { cat "$tmp/output"; fail "success path"; }
[[ -f "$repository/new-file" ]] || fail "latest upstream was not pulled"
[[ "$(git -C "$repository" status --porcelain)" = "$before" ]] || fail "index or local files changed"
[[ "$(cat "$repository/tracked")" = $'staged\nunstaged' ]] || fail "local content changed"
[[ "$(git -C "$repository" show :tracked)" = staged ]] || fail "staged content changed"
[[ "$(git -C "$repository" rev-parse refs/stash)" = "$old_stash" ]] || fail "previous stash changed"
[[ "$(cat "$repository/ignored")" = private ]] || fail "ignored file changed"
grep -Fxq "$repository#darwinConfigurations.Test-Mac.system" "$BUILD_LOG" || fail "wrong build target"
grep -q 'Nix build succeeded' "$NOTIFICATION_LOG" || fail "missing success notification"
run || { cat "$tmp/output"; fail "repeat run"; }

setup merge-failure
echo dirty > "$repository/tracked"
echo untracked > "$repository/local"
before="$(git -C "$repository" status --porcelain)"
advance merge-failure new-file
export FAIL_MERGE=1
if run; then fail "merge failure accepted"; fi
[[ "$(git -C "$repository" status --porcelain)" = "$before" ]] || fail "local files lost on merge failure"
[[ "$(cat "$repository/tracked")" = dirty ]] || fail "local content lost on merge failure"
[[ ! -f "$BUILD_LOG" ]] || fail "built despite merge failure"
if git -C "$repository" rev-parse --verify refs/stash >/dev/null 2>&1; then fail "restored stash left behind"; fi

setup divergent
echo local > "$repository/local-commit"
git -C "$repository" add .
git -C "$repository" -c commit.gpgsign=false commit -qm local
echo dirty > "$repository/tracked"
advance divergent new-file
if run; then fail "divergent branch accepted"; fi
[[ "$(cat "$repository/tracked")" = dirty ]] || fail "local edit lost on pull failure"
[[ ! -f "$BUILD_LOG" ]] || fail "built despite failed pull"
grep -q 'Nix build failed' "$NOTIFICATION_LOG" || fail "missing failure notification"

setup conflict
echo dirty > "$repository/tracked"
advance conflict tracked
if run; then fail "stash conflict accepted"; fi
[[ ! -f "$BUILD_LOG" ]] || fail "built despite stash conflict"
git -C "$repository" rev-parse refs/stash >/dev/null || fail "conflicting stash lost"
grep -q 'Local edits remain saved in stash' "$tmp/output" || fail "missing recovery instructions"

setup build-failure
export BUILD_STATUS=42
if run; then fail "failed build accepted"; fi
grep -q 'Nix build failed' "$NOTIFICATION_LOG" || fail "missing build failure notification"

setup build-log
run || { cat "$tmp/output"; fail "build log run"; }
log_file="$tmp/build-log/state/nix-pull-build/Test-Mac.log"
[[ -f "$log_file" ]] || fail "build log not created under XDG_STATE_HOME"
grep -Fxq 'fake build stdout' "$log_file" || fail "build log missing stdout"
grep -Fxq 'fake build stderr' "$log_file" || fail "build log missing stderr"
grep -Fxq -- '--print-build-logs' "$BUILD_LOG" || fail "nix not run with --print-build-logs"
grep -Fxq "Build log (live): $log_file" "$tmp/output" || fail "log path not announced"
[[ "$(grep -c 'fake build stderr' "$tmp/output")" -eq 1 ]] || fail "build output not streamed exactly once"
printf 'stale\n' >> "$log_file"
run || { cat "$tmp/output"; fail "build log rerun"; }
if grep -q stale "$log_file"; then fail "build log not truncated per run"; fi

setup build-log-failure
export BUILD_STATUS=42
if run; then fail "failed build with log accepted"; fi
grep -Fxq 'fake build stderr' "$tmp/build-log-failure/state/nix-pull-build/Test-Mac.log" || fail "failed build not logged"
grep -q 'Nix build failed' "$NOTIFICATION_LOG" || fail "missing failure notification with log"

if script --version 2>&1 | grep -q util-linux; then
  setup build-tty
  script -qec "cd '$tmp' && bash -c 'configured_repository=\"\$1\"; expected_origin=\"\$2\"; script=\"\$3\"; shift 3; source \"\$script\"' bash '$repository' '$tmp/build-tty/origin' '$script'" /dev/null \
    > "$tmp/output" 2>&1 || { cat "$tmp/output"; fail "TTY build"; }
  if grep -Fxq -- '--print-build-logs' "$BUILD_LOG"; then fail "TTY build used --print-build-logs"; fi
  [[ ! -e "$XDG_STATE_HOME" ]] || fail "TTY build wrote a log file"
  if grep -q 'Build log' "$tmp/output"; then fail "TTY build announced a log"; fi
else
  echo "skipping TTY test: util-linux script not available" >&2
fi

setup drop-failure
echo dirty > "$repository/tracked"
export FAIL_DROP=1
if run; then fail "stash cleanup failure hidden"; fi
[[ "$(cat "$repository/tracked")" = dirty ]] || fail "edits not restored on cleanup failure"
[[ ! -f "$BUILD_LOG" ]] || fail "built despite failed stash cleanup"
git -C "$repository" rev-parse refs/stash >/dev/null || fail "stash lost on cleanup failure"

setup wrong-branch
git -C "$repository" switch -qc feature
if run; then fail "feature branch accepted"; fi
[[ ! -f "$BUILD_LOG" ]] || fail "built a feature branch"

setup locked
mkdir "$repository/.git/nix-pull-build.lock"
if run; then fail "concurrent run accepted"; fi
[[ -d "$repository/.git/nix-pull-build.lock" ]] || fail "removed another run's lock"
[[ ! -f "$BUILD_LOG" ]] || fail "built despite lock"

setup arguments
if run unexpected; then fail "arguments accepted"; fi
[[ ! -f "$BUILD_LOG" ]] || fail "built despite extra arguments"

setup notification-failure
export NOTIFICATION_STATUS=7
if run; then fail "notification failure hidden"; fi
grep -q 'Build succeeded, but the notification failed' "$tmp/output" || fail "missing notification error"

setup linux
export TEST_PLATFORM=Linux
run || { cat "$tmp/output"; fail "Linux build"; }
grep -Fxq "$repository#nixosConfigurations.Test-Mac.config.system.build.toplevel" "$BUILD_LOG" || fail "wrong NixOS target"
grep -q '^notify-send$' "$NOTIFICATION_LOG" || fail "Linux did not use notify-send"
if grep -q sandbox "$BUILD_LOG"; then fail "disabled Linux sandbox"; fi
grep -q 'homeConfigurations' "$TARGET_LOG" || fail "missing standalone profile selection"

setup standalone
export TEST_PLATFORM=Linux TEST_TARGET=homeConfigurations.ali.activationPackage
run || { cat "$tmp/output"; fail "standalone Home Manager build"; }
grep -Fxq "$repository#homeConfigurations.ali.activationPackage" "$BUILD_LOG" || fail "wrong standalone target"

setup real-nixos-selector
export TEST_PLATFORM=Linux REAL_PROFILE_SELECTION=1
run || { cat "$tmp/output"; fail "real NixOS profile selection"; }
grep -Fxq "$repository#nixosConfigurations.\"Test-Mac\".config.system.build.toplevel" "$BUILD_LOG" || fail "real selector chose wrong NixOS target"

setup real-home-selector
export TEST_PLATFORM=Linux REAL_PROFILE_SELECTION=1
sed '/nixosConfigurations.Test-Mac/d' "$repository/flake.nix" > "$tmp/flake.nix"
cp "$tmp/flake.nix" "$repository/flake.nix"
run || { cat "$tmp/output"; fail "real Home Manager profile selection"; }
grep -Fxq "$repository#homeConfigurations.\"TestUser@Test-Mac\".activationPackage" "$BUILD_LOG" || fail "real selector chose wrong Home Manager target"

setup real-host-selector
export TEST_PLATFORM=Linux REAL_PROFILE_SELECTION=1
sed -e '/nixosConfigurations.Test-Mac/d' -e '/"TestUser@Test-Mac"/d' "$repository/flake.nix" > "$tmp/flake.nix"
cp "$tmp/flake.nix" "$repository/flake.nix"
run || { cat "$tmp/output"; fail "real hostname profile selection"; }
grep -Fxq "$repository#homeConfigurations.\"Test-Mac\".activationPackage" "$BUILD_LOG" || fail "real selector chose wrong hostname target"

setup real-user-selector
export TEST_PLATFORM=Linux REAL_PROFILE_SELECTION=1
sed -e '/nixosConfigurations.Test-Mac/d' -e '/"TestUser@Test-Mac"/d' -e '/Test-Mac =/d' "$repository/flake.nix" > "$tmp/flake.nix"
cp "$tmp/flake.nix" "$repository/flake.nix"
run || { cat "$tmp/output"; fail "real username profile selection"; }
grep -Fxq "$repository#homeConfigurations.\"TestUser\".activationPackage" "$BUILD_LOG" || fail "real selector chose wrong username target"

setup real-missing-selector
export TEST_PLATFORM=Linux REAL_PROFILE_SELECTION=1
echo '{ outputs = { self }: {}; }' > "$repository/flake.nix"
if run; then fail "real selector accepted missing profile"; fi
grep -q 'No NixOS or Home Manager profile found' "$tmp/output" || fail "missing profile error"
[[ ! -f "$BUILD_LOG" ]] || fail "built missing profile"

setup linux-missing-profile
export TEST_PLATFORM=Linux TARGET_STATUS=1
if run; then fail "missing Linux profile accepted"; fi
[[ ! -f "$BUILD_LOG" ]] || fail "built without a matching profile"
grep -q 'Nix build failed' "$NOTIFICATION_LOG" || fail "missing profile failure notification"

setup linux-build-failure
export TEST_PLATFORM=Linux BUILD_STATUS=42
if run; then fail "Linux build failure hidden"; fi
grep -q '^notify-send$' "$NOTIFICATION_LOG" || fail "Linux failure did not use notify-send"
grep -q 'Nix build failed' "$NOTIFICATION_LOG" || fail "missing Linux build failure notification"

setup wrong-platform
export TEST_PLATFORM=FreeBSD
if run; then fail "unsupported platform accepted"; fi
[[ ! -f "$BUILD_LOG" ]] || fail "built on unsupported platform"

setup discover-subdir
mkdir "$repository/sub"
RUN_DIR="$repository/sub" CONFIGURED="" run || { cat "$tmp/output"; fail "discovery from a subdirectory"; }
grep -Fxq "$repository#darwinConfigurations.Test-Mac.system" "$BUILD_LOG" || fail "subdirectory did not build the checkout"

setup discover-worktree
git -C "$repository" worktree add -q -b feature "$tmp/discover-worktree/wt"
RUN_DIR="$tmp/discover-worktree/wt" CONFIGURED="" run || { cat "$tmp/output"; fail "discovery from a worktree"; }
grep -Fxq "$repository#darwinConfigurations.Test-Mac.system" "$BUILD_LOG" || fail "worktree did not resolve to the main checkout"

setup discover-over-configured
git clone -q "$tmp/discover-over-configured/origin" "$tmp/discover-over-configured/other"
RUN_DIR="$repository" CONFIGURED="$tmp/discover-over-configured/other" run || { cat "$tmp/output"; fail "discovery beat the configured path"; }
grep -Fxq "$repository#darwinConfigurations.Test-Mac.system" "$BUILD_LOG" || fail "configured path beat discovery"

setup foreign-origin-fallback
git clone -q "$tmp/foreign-origin-fallback/origin" "$tmp/foreign-origin-fallback/other"
RUN_DIR="$tmp/foreign-origin-fallback/other" EXPECTED_ORIGIN=https://example.invalid/nix-config.git run \
  || { cat "$tmp/output"; fail "foreign origin should fall back to the configured path"; }
grep -Fxq "$repository#darwinConfigurations.Test-Mac.system" "$BUILD_LOG" || fail "foreign checkout was built instead of the configured one"

setup foreign-origin-no-fallback
if RUN_DIR="$repository" CONFIGURED="" EXPECTED_ORIGIN=https://example.invalid/nix-config.git run; then
  fail "checkout with a foreign origin accepted"
fi
grep -q 'programs.nix-pull-build.repository is unset' "$tmp/output" || fail "missing discovery failure message"
[[ ! -f "$BUILD_LOG" ]] || fail "built a checkout with a foreign origin"

eval "$(sed -n '/^normalize_remote()/,/^}/p' "$script")"
for url in git@github.com:o/r.git https://github.com/o/r.git https://github.com/o/r ssh://git@github.com/o/r.git; do
  [[ "$(normalize_remote "$url")" = github.com/o/r ]] || fail "normalize_remote mangled $url"
done
[[ "$(normalize_remote "/srv/git/origin")" = /srv/git/origin ]] || fail "normalize_remote mangled a local path"

echo 'All nix-pull-build integration tests passed.'
