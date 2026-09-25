#!/usr/bin/env bash
# Runs a task as an *agent* on the active local profile: the model gets
# opencode's read, glob, grep and list tools over one directory and can look
# things up itself, instead of needing every byte pasted into the prompt
# (delegate-to-local.sh). With LOCAL_LLM_AGENT_EDIT=1 it may also edit files
# in that directory; the script snapshots the directory first and writes a
# diff afterwards, for review before anything is kept. It never runs
# commands, fetches URLs, starts sub-agents, or touches anything outside the
# directory. See ../delegate-to-local.md ("Agent mode", "Edit mode").
#
# opencode runs against an isolated home ($state_dir/agent-home), not the
# user's: the global opencode config adds ~14k tokens of skills, MCP tools
# and instructions (17,249-token first request, measured 2026-09-25), more
# than a 16k local context holds, and it allows every tool.
#
# Exit codes follow delegate-to-local.sh's contract, plus 5:
#   1 = usage/dependency/config error
#   2 = no profile active, or it isn't responding: fall back to another
#       delegate
#   3 = the run failed or timed out
#   4 = LOCAL_LLM_EXPECT_PROFILE doesn't match the active profile
#   5 = the task outgrew the model's context: split it, or use a profile
#       with more context
#   6 = the run changed files that execute later (.git/, .envrc): review
#       before keeping
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/queue-common.sh
source "$script_dir/lib/queue-common.sh"

usage() {
  echo "usage: $0 <directory> <task>" >&2
  echo "env: LOCAL_LLM_EXPECT_PROFILE (exit 4 unless this profile is active)," >&2
  echo "     LOCAL_LLM_AGENT_TIMEOUT (seconds for the whole run, default 600)," >&2
  echo "     LOCAL_LLM_AGENT_LOG (where to keep the run's event log; default under the state dir)," >&2
  echo "     LOCAL_LLM_AGENT_EDIT=1 (allow edits inside <directory>; writes <log>.diff and keeps a snapshot)," >&2
  echo "     LOCAL_LLM_PROFILES_FILE, LOCAL_LLM_STATE_DIR, OPENCODE_BIN" >&2
  echo "exit codes: 1 usage/config, 2 no profile, 3 run failed/timed out, 4 wrong profile, 5 context overflow," >&2
  echo "            6 = the run changed files that execute later (.git/, .envrc): review before keeping" >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi
work_dir="$1"
task="$2"
if [[ ! -d "$work_dir" ]]; then
  echo "error: not a directory: $work_dir" >&2
  exit 1
fi
work_dir="$(cd "$work_dir" && pwd)"

opencode_bin="${OPENCODE_BIN:-opencode}"
for bin in "$opencode_bin" curl jq yq timeout; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: '$bin' not found on PATH" >&2
    exit 1
  fi
done
# 1.18.30 crashes on every prompt in SystemPrompt.environment
# ("evaluating 'a.name'", anomalyco/opencode#48965); 1.18.31 fixed it.
if "$opencode_bin" --version 2>/dev/null | grep -qx '1\.18\.30'; then
  echo "error: opencode 1.18.30 crashes on every prompt (anomalyco/opencode#48965); need 1.18.31 or later" >&2
  exit 1
fi

state_dir="$(resolve_local_llm_state_dir)" || {
  echo "error: none of LOCAL_LLM_STATE_DIR, XDG_CACHE_HOME, or HOME are set" >&2
  exit 1
}
active_file="$state_dir/active-profile.json"
if [[ ! -f "$active_file" ]]; then
  echo "error: no local profile is active; run switch-local-profile.sh first, or fall back to another delegate" >&2
  exit 2
fi
profile="$(jq -r '.profile' "$active_file")"
base_url="$(jq -r '.url' "$active_file")"
if [[ -n "${LOCAL_LLM_EXPECT_PROFILE:-}" && "$LOCAL_LLM_EXPECT_PROFILE" != "$profile" ]]; then
  echo "error: expected profile '$LOCAL_LLM_EXPECT_PROFILE' but '$profile' is active" >&2
  exit 4
fi
if ! curl -sS --max-time 2 "$base_url/v1/models" >/dev/null 2>&1; then
  echo "error: active profile '$profile' at $base_url is not responding; fall back to another delegate" >&2
  exit 2
fi

if [[ -n "${LOCAL_LLM_PROFILES_FILE:-}" ]]; then
  profiles_file="$LOCAL_LLM_PROFILES_FILE"
elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
  profiles_file="$XDG_CONFIG_HOME/delegate-to-local/profiles.toml"
else
  profiles_file="$HOME/.config/delegate-to-local/profiles.toml"
fi
# opencode must know the real window: told more, it overflows the server;
# told less, it compacts early.
context="$(yq -p toml -o json "$profiles_file" \
  | jq -r --arg p "$profile" '.[$p].launch_args // [] | (index("--ctx-size") // -1) as $i | if $i >= 0 then .[$i + 1] else empty end')"
if ! [[ "$context" =~ ^[0-9]+$ ]]; then
  echo "error: profile '$profile' in $profiles_file has no --ctx-size in launch_args; opencode needs the real context size" >&2
  exit 1
fi
output_limit=$((context / 4))

agent_home="$state_dir/agent-home"
mkdir -p "$agent_home/.config/opencode"
edit_permission="deny"
if [[ "${LOCAL_LLM_AGENT_EDIT:-0}" == "1" ]]; then
  edit_permission="allow"
fi
jq -n --arg url "$base_url/v1" --arg profile "$profile" --arg edit "$edit_permission" \
  --argjson context "$context" --argjson output "$output_limit" '{
  "$schema": "https://opencode.ai/config.json",
  provider: {local: {
    npm: "@ai-sdk/openai-compatible",
    options: {baseURL: $url},
    models: {($profile): {name: $profile, tool_call: true, reasoning: true,
                          limit: {context: $context, output: $output}}}
  }},
  model: ("local/" + $profile),
  small_model: ("local/" + $profile),
  share: "disabled",
  autoupdate: false,
  compaction: {auto: false},
  permission: {
    read: "allow", glob: "allow", grep: "allow", list: "allow",
    edit: $edit, bash: "deny", webfetch: "deny", websearch: "deny",
    task: "deny", skill: "deny", todowrite: "deny",
    external_directory: "deny"
  }
}' >"$agent_home/.config/opencode/opencode.json"

timeout_s="$(numeric_env_or_default LOCAL_LLM_AGENT_TIMEOUT 600)"
runs_dir="$state_dir/agent-runs"
mkdir -p "$runs_dir"
log="${LOCAL_LLM_AGENT_LOG:-$runs_dir/$(date -u +%Y%m%dT%H%M%SZ)-$$.jsonl}"

# Protect the profile for the length of the run: the agent talks to the
# server directly, not through the queue, so a switch would pull the model
# out from under it mid-task.
reservation_reason="agent run via delegate-to-local-agent.sh (pid $$)"
reservation_expires=$(($(date +%s) + timeout_s + 60))
# Another session's reservation of this profile that outlasts this run
# already protects it; replacing it would drop that protection when this
# run releases its own.
if ! jq -e --arg profile "$profile" --argjson until "$reservation_expires" \
  '.profile == $profile and .expires_at >= $until' \
  "$state_dir/reservation.json" >/dev/null 2>&1; then
  jq -nc --arg profile "$profile" --arg reason "$reservation_reason" \
    --argjson expires "$reservation_expires" \
    '{profile: $profile, reason: $reason, expires_at: $expires}' >"$state_dir/reservation.json.tmp"
  mv "$state_dir/reservation.json.tmp" "$state_dir/reservation.json"
fi
# Release it when the run ends, if it is still this run's.
release_reservation() {
  if jq -e --arg reason "$reservation_reason" '.reason == $reason' \
    "$state_dir/reservation.json" >/dev/null 2>&1; then
    rm -f "$state_dir/reservation.json"
  fi
}
trap release_reservation EXIT

# The snapshot is what an edit run is reviewed against, and what it is
# rolled back to if the review rejects it.
snapshot=""
if [[ "$edit_permission" == "allow" ]]; then
  snapshot="$log.before"
  # Snapshots are only needed until the run is reviewed; keep a week.
  find "$runs_dir" -mindepth 1 -maxdepth 1 -type d -name '*.before' -mtime +7 -exec rm -rf {} +
  cp -a "$work_dir" "$snapshot"
fi

env HOME="$agent_home" \
  XDG_CONFIG_HOME="$agent_home/.config" XDG_DATA_HOME="$agent_home/.local/share" \
  XDG_STATE_HOME="$agent_home/.local/state" XDG_CACHE_HOME="$agent_home/.cache" \
  timeout "$timeout_s" "$opencode_bin" run --dir "$work_dir" -m "local/$profile" \
  --format json -- "$task" >"$log" 2>"$log.stderr" &
oc_pid=$!

# opencode answers a context overflow by compacting and retrying. That
# loops until the timeout when the prompt alone overflows, and otherwise
# replaces the task with a summary the model then misreads: Qwen3.6-27B
# answered "I don't have access to prior conversation history" and the run
# exited 0. Auto-compaction is off above, so an overflow is an error event;
# stop at the first one. opencode's injected continue prompt is the other
# sign a compaction happened.
status=0
while kill -0 "$oc_pid" 2>/dev/null; do
  if grep -q '"type":"error"' "$log" 2>/dev/null; then
    kill "$oc_pid" 2>/dev/null || true
    break
  fi
  sleep 1
done
wait "$oc_pid" || status=$?

# Written before any exit below: a run that failed half-way through its
# edits needs reviewing most of all.
if [[ -n "$snapshot" ]]; then
  diff -ruN "$snapshot" "$work_dir" >"$log.diff" || true
fi
# Nothing changed, so there is nothing to review or undo.
if [[ -n "$snapshot" && ! -s "$log.diff" ]]; then
  echo "no changes" >&2
  rm -rf "$snapshot"
  snapshot=""
fi
if [[ -n "$snapshot" ]]; then
  echo "changed files:" >&2
  diff -rq "$snapshot" "$work_dir" >&2 || true
  echo "diff: $log.diff" >&2
  echo "undo: rm -rf '$work_dir' && cp -a '$snapshot' '$work_dir'" >&2

  # A model with edit access could write a file that runs later outside the
  # sandbox (a git hook, an .envrc direnv loads); flag those separately since
  # a long diff is easy to skim past.
  mapfile -d '' -t changed_entries < <(
    { (cd "$snapshot" && find . -mindepth 1 -print0)
      (cd "$work_dir" && find . -mindepth 1 -print0)
    } | sort -z -u
  )
  risky=()
  for rel in "${changed_entries[@]}"; do
    rel="${rel#./}"
    [[ -z "$rel" ]] && continue
    case "/$rel/" in
      */.git/*) ;;
      *) [[ "$(basename -- "$rel")" == ".envrc" ]] || continue ;;
    esac
    s="$snapshot/$rel"
    w="$work_dir/$rel"
    [[ -d "$s" || -d "$w" ]] && continue
    if [[ ! -e "$s" || ! -e "$w" ]] || ! diff -q "$s" "$w" >/dev/null 2>&1; then
      risky+=("$rel")
    fi
  done
  if [[ ${#risky[@]} -gt 0 ]]; then
    echo "error: the run changed files that run code later; review before keeping:" >&2
    printf '%s\n' "${risky[@]}" >&2
    risky_found=1
  fi
fi

# Every read of the log goes through this: under set -e, one line that is
# not JSON would otherwise end the script with jq's own exit code.
events() {
  jq -c -R 'fromjson? // empty' "$log"
}

events | jq -r 'select(.type == "tool_use") | "tool \(.part.tool) \(.part.state.status): \(.part.state.input | tojson)"' >&2
echo "event log: $log" >&2

error_name="$(events | jq -r 'select(.type == "error") | .error.name' | head -1)"
# Text parts only: a tool that read this script returns the phrase too.
if events | jq -r 'select(.type == "text") | .part.text' | grep -q 'Continue if you have next steps'; then
  echo "error: the conversation was compacted mid-task, so the reply cannot be trusted" >&2
  exit 5
fi
if [[ "$error_name" == "ContextOverflowError" ]]; then
  events | jq -r 'select(.type == "error") | .error.data.message' | head -1 >&2
  exit 5
fi
if [[ -n "$error_name" ]]; then
  echo "error: opencode reported $error_name:" >&2
  events | jq -r 'select(.type == "error") | .error.data.message // .error' | head -1 >&2
  exit 3
fi
if [[ "$status" -eq 124 ]]; then
  echo "error: the run did not finish within ${timeout_s}s" >&2
  exit 3
fi
if [[ "$status" -ne 0 ]]; then
  echo "error: opencode exited $status; see $log.stderr" >&2
  exit 3
fi

reply="$(events | jq -rs '[.[] | select(.type == "text") | .part.text] | last // empty')"
if [[ -z "$reply" ]]; then
  echo "error: the run finished without a reply" >&2
  exit 3
fi
printf '%s\n' "$reply"
if [[ "${risky_found:-0}" -eq 1 ]]; then
  exit 6
fi
