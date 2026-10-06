#!/usr/bin/env bats

load 'sandbox-path-helpers'

# Extracts the add_dir field's value from a FAKE_COPILOT_CALLS line (field
# 6 of 8, tab-separated) — not just the tail of the line, since gh_host and
# copilot_gh_host fields follow it.
add_dir_of() {
  local field
  field="$(cut -f6 -d"$(printf '\t')" <<<"$1")"
  echo "${field#add_dir=}"
}

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  delegate="$script_dir/../delegate.sh"
  stage_fakes_and_export_path "$script_dir"
  export FAKE_COPILOT_CALLS="$BATS_TEST_TMPDIR/calls.log"
  : >"$FAKE_COPILOT_CALLS"
  export DELEGATE_RETRY_BASE_DELAY=0
  export DELEGATE_STATE_DIR="$BATS_TEST_TMPDIR/state"
}

@test "no args prints usage and exits 1" {
  run bash "$delegate"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"[profile]"* ]]
  [[ "$output" == *"profile defaults to 'read'"* ]]
  [[ "$output" == *"valid profiles: read, write-workdir, write-and-test, read-shell, write-shell"* ]]
}

@test "missing copilot CLI prints a clear error and exits 1" {
  bash_bin="$(command -v bash)"
  empty_dir="$BATS_TEST_TMPDIR/empty-path"
  mkdir -p "$empty_dir"
  PATH="$empty_dir" run "$bash_bin" "$delegate" "task" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"'copilot' CLI not found on PATH"* ]]
  [[ "$output" == *"npm install -g @github/copilot"* ]]
}

@test "too many args prints usage and exits 1" {
  run bash "$delegate" "task" "read" "some-skill" "extra"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "invalid profile prints error listing valid profiles and exits 1" {
  run bash "$delegate" "task" "bogus-profile"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid profile 'bogus-profile'"* ]]
  [[ "$output" == *"valid profiles: read, write-workdir, write-and-test, read-shell, write-shell"* ]]
}

@test "default profile is read when omitted" {
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task"
  [ "$status" -eq 0 ]
  grep -q "allow_tool=read	add_dir=	" "$FAKE_COPILOT_CALLS"
}

@test "read profile maps to allow-tool=read" {
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  grep -q "allow_tool=read	add_dir=	" "$FAKE_COPILOT_CALLS"
}

@test "write-workdir profile maps to allow-tool=read,write" {
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task" write-workdir
  [ "$status" -eq 0 ]
  grep -q "allow_tool=read,write	add_dir=	" "$FAKE_COPILOT_CALLS"
}

@test "write-and-test profile maps to allow-tool=read,write,shell(npm test,pytest,cargo test)" {
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task" write-and-test
  [ "$status" -eq 0 ]
  grep -q 'allow_tool=read,write,shell(npm test,pytest,cargo test)	add_dir=	' "$FAKE_COPILOT_CALLS"
}

@test "read-shell profile allows read-only commands and denies destructive ones" {
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task" read-shell
  [ "$status" -eq 0 ]
  grep -qF 'allow_tool=read;shell(git status);' "$FAKE_COPILOT_CALLS"
  grep -qF 'shell(gh pr list)' "$FAKE_COPILOT_CALLS"
  grep -qF 'shell(kubectl get)' "$FAKE_COPILOT_CALLS"
  grep -qF 'shell(sift)' "$FAKE_COPILOT_CALLS"
  ! grep -qF 'shell(kubectl apply)' "$FAKE_COPILOT_CALLS"
  ! grep -qF 'shell(python3)' "$FAKE_COPILOT_CALLS"
  grep -qF 'deny_tool=shell(rm);shell(sudo);shell(git push)' "$FAKE_COPILOT_CALLS"
}

@test "write-shell profile adds write and test runners on top of read-shell" {
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task" write-shell
  [ "$status" -eq 0 ]
  grep -qF 'allow_tool=read,write;shell(git status);' "$FAKE_COPILOT_CALLS"
  grep -qF 'shell(pytest)' "$FAKE_COPILOT_CALLS"
  grep -qF 'shell(nix)' "$FAKE_COPILOT_CALLS"
  grep -qF 'shell(go)' "$FAKE_COPILOT_CALLS"
  grep -qF 'shell(shellcheck)' "$FAKE_COPILOT_CALLS"
  ! grep -qF 'shell(terraform apply)' "$FAKE_COPILOT_CALLS"
  grep -qF 'deny_tool=shell(rm);' "$FAKE_COPILOT_CALLS"
}

@test "DELEGATE_EXTRA_ALLOW_TOOL appends one more allow-tool value" {
  export FAKE_COPILOT_MODE=all-models-ok
  export DELEGATE_EXTRA_ALLOW_TOOL='shell(pup)'
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  grep -qF 'allow_tool=read;shell(pup)' "$FAKE_COPILOT_CALLS"
}

@test "DELEGATE_REASONING_EFFORT is passed through as --reasoning-effort" {
  export FAKE_COPILOT_MODE=all-models-ok
  export DELEGATE_REASONING_EFFORT=high
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  grep -qF 'reasoning_effort=high' "$FAKE_COPILOT_CALLS"
}

@test "an invalid DELEGATE_REASONING_EFFORT warns and is ignored" {
  export FAKE_COPILOT_MODE=all-models-ok
  export DELEGATE_REASONING_EFFORT=turbo
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: DELEGATE_REASONING_EFFORT='turbo'"* ]]
  grep -qF 'reasoning_effort=' "$FAKE_COPILOT_CALLS"
  ! grep -qF 'reasoning_effort=turbo' "$FAKE_COPILOT_CALLS"
}

@test "always passes -s and --no-ask-user" {
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  grep -q "silent=yes" "$FAKE_COPILOT_CALLS"
  grep -q "no_ask_user=yes" "$FAKE_COPILOT_CALLS"
}

@test "GH_HOST is inherited by the copilot subprocess for GitHub Enterprise" {
  export FAKE_COPILOT_MODE=all-models-ok
  export GH_HOST=github.example-enterprise.com
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  grep -q "gh_host=github.example-enterprise.com" "$FAKE_COPILOT_CALLS"
}

@test "COPILOT_GH_HOST is inherited by the copilot subprocess too" {
  export FAKE_COPILOT_MODE=all-models-ok
  export COPILOT_GH_HOST=github.example-enterprise.com
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  grep -q "copilot_gh_host=github.example-enterprise.com" "$FAKE_COPILOT_CALLS"
}

@test "no GH_HOST set: field is empty, not a stale value from a prior test" {
  export FAKE_COPILOT_MODE=all-models-ok
  unset GH_HOST COPILOT_GH_HOST
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  grep -q "gh_host=	copilot_gh_host=	deny_tool=	reasoning_effort=$" "$FAKE_COPILOT_CALLS"
}

@test "tries gpt-6-luna first" {
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 1 ]
  grep -q "model=gpt-6-luna" "$FAKE_COPILOT_CALLS"
  [[ "$output" == *"response for model=gpt-6-luna: hello task"* ]]
}

@test "falls back to gpt-5.6-luna when gpt-6-luna is rejected" {
  export FAKE_COPILOT_MODE=gpt6-rejected
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 2 ]
  sed -n '1p' "$FAKE_COPILOT_CALLS" | grep -q "model=gpt-6-luna"
  sed -n '2p' "$FAKE_COPILOT_CALLS" | grep -q "model=gpt-5.6-luna"
  [[ "$output" == *"response for model=gpt-5.6-luna: hello task"* ]]
}

@test "falls back to claude-haiku-4.5 when both lunas are rejected" {
  export FAKE_COPILOT_MODE=luna-rejected
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 3 ]
  sed -n '1p' "$FAKE_COPILOT_CALLS" | grep -q "model=gpt-6-luna"
  sed -n '2p' "$FAKE_COPILOT_CALLS" | grep -q "model=gpt-5.6-luna"
  sed -n '3p' "$FAKE_COPILOT_CALLS" | grep -q "model=claude-haiku-4.5"
  [[ "$output" == *"response for model=claude-haiku-4.5: hello task"* ]]
}

@test "fallback call keeps the same tool_scope as the primary call" {
  export FAKE_COPILOT_MODE=luna-rejected
  run bash "$delegate" "hello task" write-workdir
  [ "$status" -eq 0 ]
  sed -n '1p' "$FAKE_COPILOT_CALLS" | grep -q "allow_tool=read,write	add_dir=	"
  sed -n '2p' "$FAKE_COPILOT_CALLS" | grep -q "allow_tool=read,write	add_dir=	"
  sed -n '3p' "$FAKE_COPILOT_CALLS" | grep -q "allow_tool=read,write	add_dir=	"
}

@test "does not fall back on an unrelated failure, and surfaces it on stderr" {
  export FAKE_COPILOT_MODE=unrelated-failure
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 1 ]
  [[ "$output" == *"something else went wrong"* ]]
}

@test "does not fall back on an unrelated error that merely contains the phrase 'is not available'" {
  export FAKE_COPILOT_MODE=phrase-collision
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 1 ]
  [[ "$output" == *"requested feature is not available on this plan"* ]]
}

@test "treats an HTTP 503 as transient and retries, without relying on \\b" {
  export FAKE_COPILOT_MODE=outage-503
  export DELEGATE_RETRY_MAX=2
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 2 ]
  [[ "$output" == *"possible outage"* ]]
}

@test "retries a transient error and succeeds once it clears" {
  export FAKE_COPILOT_MODE=outage-then-ok
  export FAKE_COPILOT_OUTAGE_COUNTER="$BATS_TEST_TMPDIR/outage-counter"
  export FAKE_COPILOT_OUTAGE_SUCCEED_ON=2
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 2 ]
  [[ "$output" == *"response for model=gpt-6-luna: hello task"* ]]
}

@test "gives up after DELEGATE_RETRY_MAX transient failures and reports a possible outage" {
  export FAKE_COPILOT_MODE=outage-persistent
  export DELEGATE_RETRY_MAX=3
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 3 ]
  [[ "$output" == *"possible outage"* ]]
  [[ "$output" == *"network error"* ]]
}

@test "does not retry or switch models on credits/quota exhaustion, and says so" {
  export FAKE_COPILOT_MODE=credits-exhausted
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 1 ]
  [[ "$output" == *"exhausted credits/quota"* ]]
  [[ "$output" == *"exceeded your premium request quota"* ]]
}

@test "credits exhaustion writes a future cooldown timestamp to the state file" {
  export FAKE_COPILOT_MODE=credits-exhausted
  before="$(date +%s)"
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  cooldown_file="$DELEGATE_STATE_DIR/credits-exhausted-until"
  [ -f "$cooldown_file" ]
  cooldown_until="$(<"$cooldown_file")"
  [[ "$cooldown_until" =~ ^[0-9]+$ ]]
  [ "$cooldown_until" -gt "$before" ]
}

@test "a cached cooldown short-circuits before ever calling copilot" {
  mkdir -p "$DELEGATE_STATE_DIR"
  echo "$(( $(date +%s) + 3600 ))" >"$DELEGATE_STATE_DIR/credits-exhausted-until"
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"credits were reported exhausted"* ]]
  [[ "$output" == *"reset-credits-cooldown.sh"* ]]
  [ ! -s "$FAKE_COPILOT_CALLS" ]
}

@test "an expired cooldown does not short-circuit, and calls copilot normally" {
  mkdir -p "$DELEGATE_STATE_DIR"
  echo "$(( $(date +%s) - 10 ))" >"$DELEGATE_STATE_DIR/credits-exhausted-until"
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 1 ]
}

@test "a malformed cooldown file is ignored rather than blocking forever" {
  mkdir -p "$DELEGATE_STATE_DIR"
  echo "not-a-timestamp" >"$DELEGATE_STATE_DIR/credits-exhausted-until"
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 1 ]
}

@test "cooldown state defaults to \$HOME/.cache when DELEGATE_STATE_DIR is unset" {
  unset DELEGATE_STATE_DIR
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export FAKE_COPILOT_MODE=credits-exhausted
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ -f "$HOME/.cache/delegate-to-copilot/credits-exhausted-until" ]
}

@test "DELEGATE_STATE_DIR still caches when HOME is unset" {
  unset HOME
  export FAKE_COPILOT_MODE=credits-exhausted
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ -f "$DELEGATE_STATE_DIR/credits-exhausted-until" ]
}

@test "DELEGATE_STATE_DIR cooldown still short-circuits when HOME is unset" {
  mkdir -p "$DELEGATE_STATE_DIR"
  echo "$(( $(date +%s) + 3600 ))" >"$DELEGATE_STATE_DIR/credits-exhausted-until"
  unset HOME
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"credits were reported exhausted"* ]]
  [ ! -s "$FAKE_COPILOT_CALLS" ]
}

@test "XDG_CACHE_HOME is used when set and DELEGATE_STATE_DIR/HOME are not" {
  unset DELEGATE_STATE_DIR HOME
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/xdg-cache"
  mkdir -p "$XDG_CACHE_HOME"
  export FAKE_COPILOT_MODE=credits-exhausted
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ -f "$XDG_CACHE_HOME/delegate-to-copilot/credits-exhausted-until" ]
}

@test "with none of DELEGATE_STATE_DIR/XDG_CACHE_HOME/HOME set, delegate.sh still works, just without caching" {
  unset DELEGATE_STATE_DIR HOME XDG_CACHE_HOME
  export FAKE_COPILOT_MODE=credits-exhausted
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"exhausted credits/quota"* ]]
}

@test "reset-credits-cooldown.sh fails clearly when no state dir can be resolved" {
  unset DELEGATE_STATE_DIR HOME XDG_CACHE_HOME
  reset_script="$script_dir/../reset-credits-cooldown.sh"
  run bash "$reset_script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"can't tell where"* ]]
}

@test "DELEGATE_CREDITS_COOLDOWN_SECONDS controls how long the cooldown lasts" {
  export FAKE_COPILOT_MODE=credits-exhausted
  export DELEGATE_CREDITS_COOLDOWN_SECONDS=5
  before="$(date +%s)"
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  cooldown_until="$(<"$DELEGATE_STATE_DIR/credits-exhausted-until")"
  [ "$cooldown_until" -le "$(( before + 5 + 2 ))" ]
}

@test "a non-integer DELEGATE_CREDITS_COOLDOWN_SECONDS warns and falls back to the default instead of crashing" {
  export FAKE_COPILOT_MODE=credits-exhausted
  export DELEGATE_CREDITS_COOLDOWN_SECONDS=abc
  before="$(date +%s)"
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"warning: DELEGATE_CREDITS_COOLDOWN_SECONDS='abc'"* ]]
  cooldown_until="$(<"$DELEGATE_STATE_DIR/credits-exhausted-until")"
  # falls back to the 86400s default, not a crash and not treating "abc" as 0
  [ "$cooldown_until" -ge "$(( before + 86400 - 2 ))" ]
}

@test "a non-integer DELEGATE_RETRY_MAX warns and falls back to the default instead of aborting under set -e" {
  export FAKE_COPILOT_MODE=outage-persistent
  export DELEGATE_RETRY_MAX=nope
  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"warning: DELEGATE_RETRY_MAX='nope'"* ]]
  [[ "$output" == *"possible outage"* ]]
  # default retry_max is 3
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 3 ]
}

@test "a non-integer DELEGATE_RETRY_BASE_DELAY warns and falls back to the default" {
  export FAKE_COPILOT_MODE=outage-then-ok
  export FAKE_COPILOT_OUTAGE_COUNTER="$BATS_TEST_TMPDIR/outage-counter"
  export FAKE_COPILOT_OUTAGE_SUCCEED_ON=2
  export DELEGATE_RETRY_BASE_DELAY=negative-two
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning: DELEGATE_RETRY_BASE_DELAY='negative-two'"* ]]
  [[ "$output" == *"response for model=gpt-6-luna: hello task"* ]]
}

@test "reset-credits-cooldown.sh clears an existing cooldown" {
  reset_script="$script_dir/../reset-credits-cooldown.sh"
  mkdir -p "$DELEGATE_STATE_DIR"
  cooldown_file="$DELEGATE_STATE_DIR/credits-exhausted-until"
  echo "$(( $(date +%s) + 3600 ))" >"$cooldown_file"
  run bash "$reset_script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared: $cooldown_file"* ]]
  [ ! -f "$cooldown_file" ]
}

@test "reset-credits-cooldown.sh is a no-op, not an error, when there's nothing to clear" {
  reset_script="$script_dir/../reset-credits-cooldown.sh"
  run bash "$reset_script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to clear"* ]]
}

@test "reset-credits-cooldown.sh unblocks a subsequent delegate.sh call for the account limit being raised" {
  export FAKE_COPILOT_MODE=all-models-ok
  reset_script="$script_dir/../reset-credits-cooldown.sh"
  mkdir -p "$DELEGATE_STATE_DIR"
  echo "$(( $(date +%s) + 3600 ))" >"$DELEGATE_STATE_DIR/credits-exhausted-until"

  run bash "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ ! -s "$FAKE_COPILOT_CALLS" ]

  run bash "$reset_script"
  [ "$status" -eq 0 ]

  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 1 ]
}

@test "no skill arg: no --add-dir and task is passed through unchanged" {
  export FAKE_COPILOT_MODE=all-models-ok
  run bash "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  grep -q "task=hello task" "$FAKE_COPILOT_CALLS"
  grep -q "add_dir=	" "$FAKE_COPILOT_CALLS"
}

@test "resolves a skill from the project .claude/skills dir, grants --add-dir to it, and prepends a read-SKILL.md instruction" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  project_dir="$BATS_TEST_TMPDIR/project"
  project_root="$project_dir/.claude/skills"
  skill_dir="$project_root/myskill"
  mkdir -p "$skill_dir" "$HOME"
  echo "---" >"$skill_dir/SKILL.md"
  cd "$project_dir"
  run bash "$delegate" "hello task" read myskill
  [ "$status" -eq 0 ]
  grep -q "add_dir=$project_root	" "$FAKE_COPILOT_CALLS"
  grep -q "read the following: $skill_dir/SKILL.md" "$FAKE_COPILOT_CALLS"
  # $HOME/.claude/skills doesn't exist here, so no user skills root got
  # staged — the prompt must not dangle a trailing "and " with nothing
  # after it (empty effective_user_skills_root interpolated in)
  grep -q "sibling directories under $project_root — read those too" "$FAKE_COPILOT_CALLS"
  ! grep -q "and  —" "$FAKE_COPILOT_CALLS"
  grep -q "Then: hello task" "$FAKE_COPILOT_CALLS"
}

@test "stages a real, user-owned copy of ~/.claude/skills and grants --add-dir to it (not the real path)" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  project_dir="$BATS_TEST_TMPDIR/project"
  project_root="$project_dir/.claude/skills"
  user_root="$HOME/.claude/skills"
  mkdir -p "$project_root/myskill" "$user_root/othersibling"
  echo "---" >"$project_root/myskill/SKILL.md"
  echo "sibling marker content" >"$user_root/othersibling/SKILL.md"
  cd "$project_dir"
  export FAKE_COPILOT_CAT_RELATIVE="othersibling/SKILL.md"
  export FAKE_COPILOT_CAT_OUT="$BATS_TEST_TMPDIR/captured.txt"
  run bash "$delegate" "hello task" read myskill
  [ "$status" -eq 0 ]

  # captured while the staged copy still existed, i.e. --add-dir on it
  # actually granted readable, dereferenced (non-symlink) content
  [ "$(cat "$FAKE_COPILOT_CAT_OUT")" = "sibling marker content" ]

  call_line="$(cat "$FAKE_COPILOT_CALLS")"
  add_dir_field="$(add_dir_of "$call_line")"
  staged_root="${add_dir_field##*,}"
  [ "$staged_root" != "$user_root" ]
}

@test "falls back to ~/.claude/skills (staged) when the skill isn't in the project" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  user_root="$HOME/.claude/skills"
  skill_dir="$user_root/globalskill"
  mkdir -p "$skill_dir" "$BATS_TEST_TMPDIR/project"
  echo "global marker content" >"$skill_dir/SKILL.md"
  cd "$BATS_TEST_TMPDIR/project"
  export FAKE_COPILOT_CAT_RELATIVE="globalskill/SKILL.md"
  export FAKE_COPILOT_CAT_OUT="$BATS_TEST_TMPDIR/captured.txt"
  run bash "$delegate" "hello task" read globalskill
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_COPILOT_CAT_OUT")" = "global marker content" ]

  call_line="$(cat "$FAKE_COPILOT_CALLS")"
  staged_root="$(add_dir_of "$call_line")"
  [[ "$call_line" == *"read the following: $staged_root/globalskill/SKILL.md"* ]]
}

@test "resolves the project skill root from the git toplevel, not just \$PWD" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  repo_root="$BATS_TEST_TMPDIR/repo"
  skill_dir="$repo_root/.claude/skills/myskill"
  mkdir -p "$skill_dir" "$repo_root/sub/deeper"
  echo "---" >"$skill_dir/SKILL.md"
  git init -q "$repo_root"
  cd "$repo_root/sub/deeper"
  run bash "$delegate" "hello task" read myskill
  [ "$status" -eq 0 ]
  grep -q "read the following: $skill_dir/SKILL.md" "$FAKE_COPILOT_CALLS"
}

@test "project skill takes precedence over a same-named global skill" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  project_dir="$BATS_TEST_TMPDIR/project"
  project_skill="$project_dir/.claude/skills/dupskill"
  global_skill="$HOME/.claude/skills/dupskill"
  mkdir -p "$project_skill" "$global_skill"
  echo "---" >"$project_skill/SKILL.md"
  echo "---" >"$global_skill/SKILL.md"
  cd "$project_dir"
  run bash "$delegate" "hello task" read dupskill
  [ "$status" -eq 0 ]
  grep -q "read the following: $project_skill/SKILL.md" "$FAKE_COPILOT_CALLS"
}

@test "cleans up the staged skills copy after running" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  project_dir="$BATS_TEST_TMPDIR/project"
  user_root="$HOME/.claude/skills"
  mkdir -p "$project_dir" "$user_root/myskill"
  echo "---" >"$user_root/myskill/SKILL.md"
  cd "$project_dir"
  run bash "$delegate" "hello task" read myskill
  [ "$status" -eq 0 ]

  call_line="$(cat "$FAKE_COPILOT_CALLS")"
  staged_root="$(add_dir_of "$call_line")"
  [ -n "$staged_root" ]
  [ ! -d "$staged_root" ]
}

@test "unknown skill errors clearly and never calls copilot" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/project"
  cd "$BATS_TEST_TMPDIR/project"
  run bash "$delegate" "hello task" read no-such-skill
  [ "$status" -eq 1 ]
  [[ "$output" == *"skill(s) 'no-such-skill' not found"* ]]
  [ ! -s "$FAKE_COPILOT_CALLS" ]
}

@test "a skills arg that's only commas/whitespace errors clearly instead of building an empty prompt" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/project"
  cd "$BATS_TEST_TMPDIR/project"
  run bash "$delegate" "hello task" read " , ,"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no valid skill names found"* ]]
  [ ! -s "$FAKE_COPILOT_CALLS" ]
}

@test "unknown skill message uses a literal ~/.claude/skills when HOME is unset, not a bogus /.claude/skills path" {
  export FAKE_COPILOT_MODE=all-models-ok
  unset HOME
  mkdir -p "$BATS_TEST_TMPDIR/project"
  cd "$BATS_TEST_TMPDIR/project"
  run bash "$delegate" "hello task" read no-such-skill
  [ "$status" -eq 1 ]
  [[ "$output" == *"skill(s) 'no-such-skill' not found"* ]]
  [[ "$output" == *"~/.claude/skills"* ]]
  [[ "$output" != *" /.claude/skills"* ]]
}

@test "accepts multiple comma-separated skills and reads all of them" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  project_dir="$BATS_TEST_TMPDIR/project"
  project_root="$project_dir/.claude/skills"
  skill_a="$project_root/skill-a"
  skill_b="$project_root/skill-b"
  mkdir -p "$skill_a" "$skill_b" "$HOME"
  echo "---" >"$skill_a/SKILL.md"
  echo "---" >"$skill_b/SKILL.md"
  cd "$project_dir"
  run bash "$delegate" "hello task" read skill-a,skill-b
  [ "$status" -eq 0 ]
  grep -q "read the following: $skill_a/SKILL.md, $skill_b/SKILL.md" "$FAKE_COPILOT_CALLS"
  grep -q "Then: hello task" "$FAKE_COPILOT_CALLS"
}

@test "trims whitespace around comma-separated skill names" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  project_dir="$BATS_TEST_TMPDIR/project"
  project_root="$project_dir/.claude/skills"
  skill_a="$project_root/skill-a"
  skill_b="$project_root/skill-b"
  mkdir -p "$skill_a" "$skill_b" "$HOME"
  echo "---" >"$skill_a/SKILL.md"
  echo "---" >"$skill_b/SKILL.md"
  cd "$project_dir"
  run bash "$delegate" "hello task" read "skill-a, skill-b"
  [ "$status" -eq 0 ]
  grep -q "read the following: $skill_a/SKILL.md, $skill_b/SKILL.md" "$FAKE_COPILOT_CALLS"
}

@test "skips an empty entry between two commas without erroring" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  project_dir="$BATS_TEST_TMPDIR/project"
  project_root="$project_dir/.claude/skills"
  skill_a="$project_root/skill-a"
  skill_b="$project_root/skill-b"
  mkdir -p "$skill_a" "$skill_b" "$HOME"
  echo "---" >"$skill_a/SKILL.md"
  echo "---" >"$skill_b/SKILL.md"
  cd "$project_dir"
  # "a,,b": bash's `read -ra` on IFS=',' does produce a genuine empty
  # field for a *middle* empty entry (unlike a trailing comma, which
  # `read` just drops) — this is the real case that needs skipping.
  run bash "$delegate" "hello task" read "skill-a,,skill-b"
  [ "$status" -eq 0 ]
  # exact match, not substring: a spurious middle entry (e.g. from an
  # unskipped empty name resolving to the skills root itself) would
  # still satisfy a plain grep -q here
  grep -q "read the following: $skill_a/SKILL.md, $skill_b/SKILL.md — and follow" "$FAKE_COPILOT_CALLS"
}

@test "multiple skills can resolve from different roots (project + global)" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  project_dir="$BATS_TEST_TMPDIR/project"
  project_skill="$project_dir/.claude/skills/project-skill"
  global_skill="$HOME/.claude/skills/global-skill"
  mkdir -p "$project_skill" "$global_skill"
  echo "---" >"$project_skill/SKILL.md"
  echo "---" >"$global_skill/SKILL.md"
  cd "$project_dir"
  run bash "$delegate" "hello task" read project-skill,global-skill
  [ "$status" -eq 0 ]

  call_line="$(cat "$FAKE_COPILOT_CALLS")"
  [[ "$call_line" == *"read the following: $project_skill/SKILL.md, "*"/global-skill/SKILL.md"* ]]
}

@test "lists all missing skills together when several are unknown" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  project_dir="$BATS_TEST_TMPDIR/project"
  project_root="$project_dir/.claude/skills"
  mkdir -p "$project_root/known" "$HOME"
  echo "---" >"$project_root/known/SKILL.md"
  cd "$project_dir"
  run bash "$delegate" "hello task" read known,missing-one,missing-two
  [ "$status" -eq 1 ]
  [[ "$output" == *"skill(s) 'missing-one,missing-two' not found"* ]]
  [ ! -s "$FAKE_COPILOT_CALLS" ]
}
