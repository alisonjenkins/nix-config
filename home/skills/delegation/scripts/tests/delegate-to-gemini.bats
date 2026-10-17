#!/usr/bin/env bats

load 'sandbox-path-helpers'

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  delegate="$script_dir/../delegate-to-gemini.sh"
  stage_fakes_and_export_path "$script_dir"
  export FAKE_AGY_CALLS="$BATS_TEST_TMPDIR/calls.log"
  : >"$FAKE_AGY_CALLS"
  unset DELEGATE_REASONING_EFFORT DELEGATE_MODEL FAKE_AGY_MODE DELEGATE_TELEMETRY \
    DELEGATE_OTLP_ENDPOINT TRACEPARENT CLAUDE_CODE_SESSION_ID XDG_STATE_HOME \
    SSH_CONNECTION XDG_RUNTIME_DIR
  export DELEGATE_RETRY_BASE_DELAY=0
  # A real ~/.config/cc-obs/endpoints.json or state dir must never be touched.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export DELEGATE_TELEMETRY_DIR="$BATS_TEST_TMPDIR/telemetry"
  calls_jsonl="$DELEGATE_TELEMETRY_DIR/gemini-calls.jsonl"
  export FAKE_CURL_CALLS="$BATS_TEST_TMPDIR/curl-calls.log"
  : >"$FAKE_CURL_CALLS"
  export FAKE_CURL_UP="http://collector.test"
}

@test "no args prints usage and exits 1" {
  run bash "$delegate"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
  [[ "$output" == *"valid profiles: read, write-workdir, write-shell"* ]]
}

@test "missing agy CLI prints a clear error and exits 1" {
  bash_bin="$(command -v bash)"
  empty_dir="$BATS_TEST_TMPDIR/empty-path"
  mkdir -p "$empty_dir"
  PATH="$empty_dir" run "$bash_bin" "$delegate" "task" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"'agy' (Antigravity CLI) not found on PATH"* ]]
}

@test "invalid profile exits 1 and lists valid profiles" {
  run bash "$delegate" "task" nonsense
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid profile 'nonsense'"* ]]
}

@test "read profile passes no permission flags" {
  run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [[ "$output" == "response for model=gemini-3.8-flash-medium: do it" ]]
  call="$(<"$FAKE_AGY_CALLS")"
  [[ "$call" == *$'mode=\tskip_perms=no'* ]]
}

@test "write-workdir uses accept-edits mode" {
  run bash "$delegate" "do it" write-workdir
  [ "$status" -eq 0 ]
  [[ "$(<"$FAKE_AGY_CALLS")" == *$'mode=accept-edits\tskip_perms=no'* ]]
}

@test "write-shell skips permissions" {
  run bash "$delegate" "do it" write-shell
  [ "$status" -eq 0 ]
  [[ "$(<"$FAKE_AGY_CALLS")" == *$'mode=\tskip_perms=yes'* ]]
}

@test "reasoning effort is passed through and a bad value is ignored" {
  DELEGATE_REASONING_EFFORT=high run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [[ "$(<"$FAKE_AGY_CALLS")" == *$'effort=high'* ]]

  : >"$FAKE_AGY_CALLS"
  DELEGATE_REASONING_EFFORT=bogus run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignoring"* ]]
  [[ "$(<"$FAKE_AGY_CALLS")" == *$'effort=\t'* ]]
}

@test "a rejected model falls back to the next one" {
  FAKE_AGY_MODE=flash-medium-rejected run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [[ "$output" == "response for model=gemini-3.8-flash-low: do it" ]]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 2 ]
}

@test "a denied command exits 3 and names write-shell" {
  FAKE_AGY_MODE=soft-denied-command run bash "$delegate" "do it" write-workdir
  [ "$status" -eq 3 ]
  [[ "$output" == *"needs write-shell"* ]]
  [[ "$output" == *"under profile 'write-workdir'"* ]]
}

@test "a denied write exits 3 and names write-workdir" {
  FAKE_AGY_MODE=soft-denied-write run bash "$delegate" "do it" read
  [ "$status" -eq 3 ]
  [[ "$output" == *"needs write-workdir"* ]]
}

@test "a failure shows agy's error once, not the raw JSON envelope as well" {
  FAKE_AGY_MODE=json-error DELEGATE_MODEL=bogus-model run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [ "$(grep -c 'not recognized as a known model' <<<"$output")" -eq 1 ]
  [[ "$output" != *'"status":"ERROR"'* ]]
  [ "$(jq -r .outcome "$calls_jsonl")" = "model_rejected" ]
}

@test "an effort error does not count as a rejected model" {
  FAKE_AGY_MODE=bad-effort run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 1 ]
}

@test "DELEGATE_MODEL picks the model and is not replaced on rejection" {
  DELEGATE_MODEL=gemini-4-argon-high run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [[ "$output" == "response for model=gemini-4-argon-high: do it" ]]

  : >"$FAKE_AGY_CALLS"
  FAKE_AGY_MODE=flash-medium-rejected DELEGATE_MODEL=gemini-3.8-flash-medium \
    run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 1 ]
}

@test "missing sign-in is reported with the fix" {
  FAKE_AGY_MODE=unauthenticated run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"not signed in"* ]]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 1 ]
  [ "$(jq -r .outcome "$calls_jsonl")" = "auth_missing" ]
}

@test "persistent outage retries then reports a possible outage" {
  FAKE_AGY_MODE=outage-persistent run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"possible outage"* ]]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 3 ]
}

@test "exhausted quota is reported and not retried" {
  FAKE_AGY_MODE=quota-exhausted run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"exhausted quota"* ]]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 1 ]
}

@test "an unrelated failure is surfaced without trying another model" {
  FAKE_AGY_MODE=unrelated-failure run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [[ "$output" == *"something else went wrong"* ]]
  [ "$(wc -l <"$FAKE_AGY_CALLS")" -eq 1 ]
}

@test "a named skill is staged and granted via --add-dir" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/skills/demo"
  echo "# demo" >"$HOME/.claude/skills/demo/SKILL.md"
  run bash "$delegate" "do it" read demo
  [ "$status" -eq 0 ]
  call="$(<"$FAKE_AGY_CALLS")"
  [[ "$call" == *"Before doing anything else, read the following:"* ]]
  [[ "$call" == *"delegate-to-gemini-skills."* ]]
}

@test "an unknown skill exits 1 naming it" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/skills"
  run bash "$delegate" "do it" read nosuchskill
  [ "$status" -eq 1 ]
  [[ "$output" == *"skill(s) 'nosuchskill' not found"* ]]
}

parent_trace="4bf92f3577b34da6a3ce929d0e0e4736"
parent_span="00f067aa0ba902b7"

@test "a call is recorded as a child of Claude's trace" {
  export TRACEPARENT="00-$parent_trace-$parent_span-01"
  export CLAUDE_CODE_SESSION_ID="sess-123"
  run bash "$delegate" "do it" write-workdir
  [ "$status" -eq 0 ]
  record="$(tail -n1 "$calls_jsonl")"
  [ "$(jq -r .trace_id <<<"$record")" = "$parent_trace" ]
  [ "$(jq -r .parent_span_id <<<"$record")" = "$parent_span" ]
  [ "$(jq -r .claude_session_id <<<"$record")" = "sess-123" ]
  [ "$(jq -r .outcome <<<"$record")" = "success" ]
  [ "$(jq -r .model <<<"$record")" = "gemini-3.8-flash-medium" ]
  [ "$(jq -r .profile <<<"$record")" = "write-workdir" ]
  [ "$(jq -r .input_tokens <<<"$record")" = "100" ]
  [ "$(jq -r .output_tokens <<<"$record")" = "20" ]
  [ "$(jq -r .thinking_tokens <<<"$record")" = "5" ]
  [[ "$(jq -r .ts <<<"$record")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
}

@test "the span is posted to the collector under the same trace" {
  export TRACEPARENT="00-$parent_trace-$parent_span-01"
  export DELEGATE_OTLP_ENDPOINT="http://collector.test"
  run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  line="$(grep 'url=http://collector.test/v1/traces' "$FAKE_CURL_CALLS")"
  body="${line#*body=}"
  span="$(jq -c '.resourceSpans[0].scopeSpans[0].spans[0]' <<<"$body")"
  [ "$(jq -r .traceId <<<"$span")" = "$parent_trace" ]
  [ "$(jq -r .parentSpanId <<<"$span")" = "$parent_span" ]
  [ "$(jq -r .status.code <<<"$span")" = "1" ]
  [ "$(jq -r '.attributes[] | select(.key=="gen_ai.usage.input_tokens") | .value.intValue' <<<"$span")" = "100" ]
  [ "$(jq -r '.attributes[] | select(.key=="delegate.profile") | .value.stringValue' <<<"$span")" = "read" ]
}

@test "agy runs under the span's own context, not Claude's" {
  export TRACEPARENT="00-$parent_trace-$parent_span-01"
  run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  child="$(sed -E -n 's/.*traceparent=([^[:space:]]*).*/\1/p' "$FAKE_AGY_CALLS")"
  span_id="$(jq -r .span_id "$calls_jsonl")"
  [ "$child" = "00-$parent_trace-$span_id-01" ]
  [ "$span_id" != "$parent_span" ]
}

@test "without a parent a new trace is started" {
  run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  record="$(tail -n1 "$calls_jsonl")"
  [[ "$(jq -r .trace_id <<<"$record")" =~ ^[0-9a-f]{32}$ ]]
  [ "$(jq -r .parent_span_id <<<"$record")" = "" ]
}

@test "a malformed or all-zero TRACEPARENT is not propagated" {
  export TRACEPARENT="00-00000000000000000000000000000000-$parent_span-01"
  run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [ "$(jq -r .parent_span_id "$calls_jsonl")" = "" ]

  : >"$calls_jsonl"
  export TRACEPARENT="garbage"
  run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [ "$(jq -r .parent_span_id "$calls_jsonl")" = "" ]
}

@test "DELEGATE_TELEMETRY=off records nothing and passes no trace context" {
  export DELEGATE_OTLP_ENDPOINT="http://collector.test"
  DELEGATE_TELEMETRY=off run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [ ! -e "$calls_jsonl" ]
  [ ! -s "$FAKE_CURL_CALLS" ]
  [[ "$(<"$FAKE_AGY_CALLS")" == *$'traceparent='* ]]
  [[ "$(<"$FAKE_AGY_CALLS")" != *"traceparent=00-"* ]]
}

@test "a down collector warns but still writes the record and succeeds" {
  export DELEGATE_OTLP_ENDPOINT="http://collector.test"
  export FAKE_CURL_UP=""
  run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not send the delegate span"* ]]
  [ "$(jq -r .outcome "$calls_jsonl")" = "success" ]
}

@test "the endpoint falls back to the observability stack's endpoints file" {
  mkdir -p "$HOME/.config/cc-obs"
  echo '{"urls":{"otlpHttp":"http://collector.test"}}' >"$HOME/.config/cc-obs/endpoints.json"
  run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  grep -q 'url=http://collector.test/v1/traces' "$FAKE_CURL_CALLS"
}

@test "failures and denials are recorded with their outcome" {
  FAKE_AGY_MODE=quota-exhausted run bash "$delegate" "do it" read
  [ "$status" -eq 1 ]
  [ "$(jq -r .outcome "$calls_jsonl")" = "quota" ]
  [ "$(jq -r .exit_code "$calls_jsonl")" = "1" ]

  : >"$calls_jsonl"
  FAKE_AGY_MODE=soft-denied-command run bash "$delegate" "do it" write-workdir
  [ "$status" -eq 3 ]
  [ "$(jq -r .outcome "$calls_jsonl")" = "denied" ]
  [ "$(jq -r '.denied_actions | join(",")' "$calls_jsonl")" = "command" ]

  : >"$calls_jsonl"
  FAKE_AGY_MODE=outage-persistent run bash "$delegate" "do it" read
  [ "$(jq -r .outcome "$calls_jsonl")" = "transient_exhausted" ]
  [ "$(jq -r .attempts "$calls_jsonl")" = "3" ]
}

@test "no prompt or answer text reaches the record or the span" {
  export DELEGATE_OTLP_ENDPOINT="http://collector.test"
  run bash "$delegate" "SECRETWORD in the task" read
  [ "$status" -eq 0 ]
  ! grep -q SECRETWORD "$calls_jsonl"
  ! grep -q SECRETWORD "$FAKE_CURL_CALLS"
}

@test "SSH_CONNECTION is unset when a local session bus exists" {
  export SSH_CONNECTION="10.0.0.1 12345 10.0.0.2 22"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime-bus"
  mkdir -p "$XDG_RUNTIME_DIR"
  touch "$XDG_RUNTIME_DIR/bus"
  run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  call="$(<"$FAKE_AGY_CALLS")"
  [[ "$call" == *$'\tssh_connection=' ]]
}

@test "SSH_CONNECTION is preserved when no local session bus exists" {
  export SSH_CONNECTION="10.0.0.1 12345 10.0.0.2 22"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime-no-bus"
  mkdir -p "$XDG_RUNTIME_DIR"
  run bash "$delegate" "do it" read
  [ "$status" -eq 0 ]
  call="$(<"$FAKE_AGY_CALLS")"
  [[ "$call" == *$'\tssh_connection=10.0.0.1 12345 10.0.0.2 22' ]]
}
