#!/usr/bin/env bats
# Edit mode's review contract: what a run changed is reported, and a change
# to a file that runs code later is never hidden behind another exit code.

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  agent="$script_dir/../delegate-to-local-agent.sh"
  export PATH="$script_dir:$PATH"
  export LOCAL_LLM_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export LOCAL_LLM_PROFILES_FILE="$BATS_TEST_TMPDIR/profiles.toml"
  export FAKE_CURL_CALLS="$BATS_TEST_TMPDIR/curl-calls.log"
  export FAKE_CURL_UP="http://localhost:8080"
  export LOCAL_LLM_AGENT_EDIT=1
  export OPENCODE_BIN="$BATS_TEST_TMPDIR/opencode"
  unset FAKE_OC_WRITE FAKE_OC_EXIT LOCAL_LLM_EXPECT_PROFILE LOCAL_LLM_AGENT_LOG
  : >"$FAKE_CURL_CALLS"

  mkdir -p "$LOCAL_LLM_STATE_DIR"
  jq -nc '{profile: "fast", url: "http://localhost:8080", model: "m", pid: 999999999}' \
    >"$LOCAL_LLM_STATE_DIR/active-profile.json"
  cat >"$LOCAL_LLM_PROFILES_FILE" <<'TOML'
[fast]
runtime = "llama-server"
model = "/models/x.gguf"
launch_args = ["--ctx-size", "8192"]
TOML

  # Writes $FAKE_OC_WRITE (relative to --dir), replies, then exits
  # $FAKE_OC_EXIT, like a run that edited and then failed or finished.
  cat >"$OPENCODE_BIN" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then echo 1.18.31; exit 0; fi
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--dir" ]]; then dir="$2"; shift; fi
  shift
done
if [[ -n "${FAKE_OC_WRITE:-}" ]]; then
  mkdir -p "$(dirname "$dir/$FAKE_OC_WRITE")"
  echo "written by the model" >"$dir/$FAKE_OC_WRITE"
fi
echo '{"type":"text","part":{"text":"done"}}'
exit "${FAKE_OC_EXIT:-0}"
SH
  chmod +x "$OPENCODE_BIN"

  work="$BATS_TEST_TMPDIR/work"
  mkdir -p "$work/.git/hooks"
  echo original >"$work/file.txt"
}

@test "a changed git hook exits 6 after printing the reply" {
  export FAKE_OC_WRITE=".git/hooks/pre-commit"
  run "$agent" "$work" "task"
  [ "$status" -eq 6 ]
  [[ "$output" == *".git/hooks/pre-commit"* ]]
  [[ "$output" == *"done"* ]]
}

@test "a changed git hook exits 6 even when the run failed" {
  # A failed run's exit code must not hide a hook it left behind.
  export FAKE_OC_WRITE=".git/hooks/pre-commit"
  export FAKE_OC_EXIT=1
  run "$agent" "$work" "task"
  [ "$status" -eq 6 ]
  [[ "$output" == *"opencode exited 1"* ]]
}

@test "a failed run that changed nothing risky keeps its own exit code" {
  export FAKE_OC_WRITE="file.txt"
  export FAKE_OC_EXIT=1
  run "$agent" "$work" "task"
  [ "$status" -eq 3 ]
}

@test "the printed undo command restores a directory whose path has a quote" {
  local quoted="$BATS_TEST_TMPDIR/it's here"
  mv "$work" "$quoted"
  export FAKE_OC_WRITE="file.txt"
  run "$agent" "$quoted" "task"
  [ "$status" -eq 0 ]
  local undo
  undo="$(grep '^undo: ' <<<"$output")"
  bash -c "${undo#undo: }"
  [ "$(cat "$quoted/file.txt")" = "original" ]
}
