#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  delegate="$script_dir/../scripts/delegate.sh"
  export PATH="$script_dir:$PATH"
  export FAKE_COPILOT_CALLS="$BATS_TEST_TMPDIR/calls.log"
  : >"$FAKE_COPILOT_CALLS"
  export DELEGATE_RETRY_BASE_DELAY=0
}

@test "no args prints usage and exits 1" {
  run "$delegate"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"valid profiles: read, write-workdir, write-and-test"* ]]
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
  run "$delegate" "task" "read" "some-skill" "extra"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "invalid profile prints error listing valid profiles and exits 1" {
  run "$delegate" "task" "bogus-profile"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid profile 'bogus-profile'"* ]]
  [[ "$output" == *"valid profiles: read, write-workdir, write-and-test"* ]]
}

@test "default profile is read when omitted" {
  export FAKE_COPILOT_MODE=all-models-ok
  run "$delegate" "hello task"
  [ "$status" -eq 0 ]
  grep -q "allow_tool=read	add_dir=$" "$FAKE_COPILOT_CALLS"
}

@test "read profile maps to allow-tool=read" {
  export FAKE_COPILOT_MODE=all-models-ok
  run "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  grep -q "allow_tool=read	add_dir=$" "$FAKE_COPILOT_CALLS"
}

@test "write-workdir profile maps to allow-tool=read,write" {
  export FAKE_COPILOT_MODE=all-models-ok
  run "$delegate" "hello task" write-workdir
  [ "$status" -eq 0 ]
  grep -q "allow_tool=read,write	add_dir=$" "$FAKE_COPILOT_CALLS"
}

@test "write-and-test profile maps to allow-tool=read,write,shell(npm test,pytest,cargo test)" {
  export FAKE_COPILOT_MODE=all-models-ok
  run "$delegate" "hello task" write-and-test
  [ "$status" -eq 0 ]
  grep -q 'allow_tool=read,write,shell(npm test,pytest,cargo test)	add_dir=$' "$FAKE_COPILOT_CALLS"
}

@test "always passes -s and --no-ask-user" {
  export FAKE_COPILOT_MODE=all-models-ok
  run "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  grep -q "silent=yes" "$FAKE_COPILOT_CALLS"
  grep -q "no_ask_user=yes" "$FAKE_COPILOT_CALLS"
}

@test "tries gpt-5.6-luna first" {
  export FAKE_COPILOT_MODE=all-models-ok
  run "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 1 ]
  grep -q "model=gpt-5.6-luna" "$FAKE_COPILOT_CALLS"
  [[ "$output" == *"response for model=gpt-5.6-luna: hello task"* ]]
}

@test "falls back to claude-haiku-4.5 when luna is rejected" {
  export FAKE_COPILOT_MODE=luna-rejected
  run "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 2 ]
  sed -n '1p' "$FAKE_COPILOT_CALLS" | grep -q "model=gpt-5.6-luna"
  sed -n '2p' "$FAKE_COPILOT_CALLS" | grep -q "model=claude-haiku-4.5"
  [[ "$output" == *"response for model=claude-haiku-4.5: hello task"* ]]
}

@test "fallback call keeps the same tool_scope as the primary call" {
  export FAKE_COPILOT_MODE=luna-rejected
  run "$delegate" "hello task" write-workdir
  [ "$status" -eq 0 ]
  sed -n '1p' "$FAKE_COPILOT_CALLS" | grep -q "allow_tool=read,write	add_dir=$"
  sed -n '2p' "$FAKE_COPILOT_CALLS" | grep -q "allow_tool=read,write	add_dir=$"
}

@test "does not fall back on an unrelated failure, and surfaces it on stderr" {
  export FAKE_COPILOT_MODE=unrelated-failure
  run "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 1 ]
  [[ "$output" == *"something else went wrong"* ]]
}

@test "does not fall back on an unrelated error that merely contains the phrase 'is not available'" {
  export FAKE_COPILOT_MODE=phrase-collision
  run "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 1 ]
  [[ "$output" == *"requested feature is not available on this plan"* ]]
}

@test "treats an HTTP 503 as transient and retries, without relying on \\b" {
  export FAKE_COPILOT_MODE=outage-503
  export DELEGATE_RETRY_MAX=2
  run "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 2 ]
  [[ "$output" == *"possible outage"* ]]
}

@test "retries a transient error and succeeds once it clears" {
  export FAKE_COPILOT_MODE=outage-then-ok
  export FAKE_COPILOT_OUTAGE_COUNTER="$BATS_TEST_TMPDIR/outage-counter"
  export FAKE_COPILOT_OUTAGE_SUCCEED_ON=2
  run "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 2 ]
  [[ "$output" == *"response for model=gpt-5.6-luna: hello task"* ]]
}

@test "gives up after DELEGATE_RETRY_MAX transient failures and reports a possible outage" {
  export FAKE_COPILOT_MODE=outage-persistent
  export DELEGATE_RETRY_MAX=3
  run "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 3 ]
  [[ "$output" == *"possible outage"* ]]
  [[ "$output" == *"network error"* ]]
}

@test "does not retry or switch models on credits/quota exhaustion, and says so" {
  export FAKE_COPILOT_MODE=credits-exhausted
  run "$delegate" "hello task" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_COPILOT_CALLS")" -eq 1 ]
  [[ "$output" == *"exhausted credits/quota"* ]]
  [[ "$output" == *"exceeded your premium request quota"* ]]
}

@test "no skill arg: no --add-dir and task is passed through unchanged" {
  export FAKE_COPILOT_MODE=all-models-ok
  run "$delegate" "hello task" read
  [ "$status" -eq 0 ]
  grep -q "task=hello task" "$FAKE_COPILOT_CALLS"
  grep -q "add_dir=$" "$FAKE_COPILOT_CALLS"
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
  run "$delegate" "hello task" read myskill
  [ "$status" -eq 0 ]
  grep -q "add_dir=$project_root$" "$FAKE_COPILOT_CALLS"
  grep -q "read $skill_dir/SKILL.md and follow its instructions" "$FAKE_COPILOT_CALLS"
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
  run "$delegate" "hello task" read myskill
  [ "$status" -eq 0 ]

  # captured while the staged copy still existed, i.e. --add-dir on it
  # actually granted readable, dereferenced (non-symlink) content
  [ "$(cat "$FAKE_COPILOT_CAT_OUT")" = "sibling marker content" ]

  call_line="$(cat "$FAKE_COPILOT_CALLS")"
  add_dir_field="${call_line##*add_dir=}"
  staged_root="${add_dir_field##*,}"
  [ "$staged_root" != "$user_root" ]
  [[ "$staged_root" != "$HOME"* ]]
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
  run "$delegate" "hello task" read globalskill
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_COPILOT_CAT_OUT")" = "global marker content" ]

  call_line="$(cat "$FAKE_COPILOT_CALLS")"
  staged_root="${call_line##*add_dir=}"
  [[ "$call_line" == *"read $staged_root/globalskill/SKILL.md and follow its instructions"* ]]
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
  run "$delegate" "hello task" read myskill
  [ "$status" -eq 0 ]
  grep -q "read $skill_dir/SKILL.md and follow its instructions" "$FAKE_COPILOT_CALLS"
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
  run "$delegate" "hello task" read dupskill
  [ "$status" -eq 0 ]
  grep -q "read $project_skill/SKILL.md and follow its instructions" "$FAKE_COPILOT_CALLS"
}

@test "cleans up the staged skills copy after running" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  project_dir="$BATS_TEST_TMPDIR/project"
  user_root="$HOME/.claude/skills"
  mkdir -p "$project_dir" "$user_root/myskill"
  echo "---" >"$user_root/myskill/SKILL.md"
  cd "$project_dir"
  run "$delegate" "hello task" read myskill
  [ "$status" -eq 0 ]

  call_line="$(cat "$FAKE_COPILOT_CALLS")"
  staged_root="${call_line##*add_dir=}"
  [ -n "$staged_root" ]
  [ ! -d "$staged_root" ]
}

@test "unknown skill errors clearly and never calls copilot" {
  export FAKE_COPILOT_MODE=all-models-ok
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/project"
  cd "$BATS_TEST_TMPDIR/project"
  run "$delegate" "hello task" read no-such-skill
  [ "$status" -eq 1 ]
  [[ "$output" == *"skill 'no-such-skill' not found"* ]]
  [ ! -s "$FAKE_COPILOT_CALLS" ]
}
