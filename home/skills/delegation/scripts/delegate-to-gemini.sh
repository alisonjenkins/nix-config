#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <task> [profile] [skill[,skill...]]" >&2
  echo "profile defaults to 'read'; give it explicitly to also pass skill" >&2
  echo "valid profiles: read, write-workdir, write-shell" >&2
  echo "skill: comma-separated Claude skill names, resolved from the project's" >&2
  echo "  .claude/skills/<skill> then ~/.claude/skills/<skill>" >&2
}

if [[ $# -lt 1 || $# -gt 3 ]]; then
  usage
  exit 1
fi

if ! command -v agy >/dev/null 2>&1; then
  echo "error: 'agy' (Antigravity CLI) not found on PATH — install antigravity-cli and run 'agy' once interactively to sign in; headless mode only reuses those cached credentials." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/delegate-telemetry.sh
source "$script_dir/lib/delegate-telemetry.sh"

task="$1"
profile="${2:-read}"
skills_arg="${3:-}"

# Headless agy auto-denies any tool that needs approval (exit 0, notice on
# stderr), so a profile is just a permission mode: default reads only,
# accept-edits also writes files, and the shell profile approves everything.
profile_args=()
case "$profile" in
  read) ;;
  write-workdir) profile_args=(--mode accept-edits) ;;
  write-shell) profile_args=(--dangerously-skip-permissions) ;;
  *)
    echo "error: invalid profile '$profile'" >&2
    echo "valid profiles: read, write-workdir, write-shell" >&2
    exit 1
    ;;
esac

numeric_env_or_default() {
  local var_name="$1" default="$2" value="${!1:-}"
  if [[ -z "$value" ]]; then
    printf '%s' "$default"
  elif [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    echo "warning: $var_name='$value' is not a non-negative integer; using default $default" >&2
    printf '%s' "$default"
  fi
}

effort_args=()
if [[ -n "${DELEGATE_REASONING_EFFORT:-}" ]]; then
  case "$DELEGATE_REASONING_EFFORT" in
    low|medium|high)
      effort_args=(--effort "$DELEGATE_REASONING_EFFORT")
      ;;
    *)
      echo "warning: DELEGATE_REASONING_EFFORT='$DELEGATE_REASONING_EFFORT' is not one of low, medium, high; ignoring" >&2
      ;;
  esac
fi

# jq turns agy's JSON envelope (answer, token usage, denied tools) into the
# call record and a structured denial check. Without it, agy runs in text mode
# and nothing is recorded.
use_json=0
command -v jq >/dev/null 2>&1 && use_json=1

# The span is a child of Claude Code's tool span (TRACEPARENT), and agy is
# started under the span's own context so a tracing hook inside agy nests
# below it.
telemetry_init
trace_env=()
telemetry_enabled && trace_env=(env "TRACEPARENT=$tel_traceparent")

# agy refuses to read outside the workspace, and ~/.claude/skills is
# home-manager-managed (symlinks into the read-only Nix store), which --add-dir
# does not make readable either. A dereferenced, user-owned copy does.
extra_args=()
staged_user_skills_root=""
err_file=""
# shellcheck disable=SC2329 # invoked indirectly via `trap`, below
cleanup_temp() {
  [[ -z "$err_file" ]] || rm -f "$err_file"
  if [[ -n "$staged_user_skills_root" ]]; then
    chmod -R u+w "$staged_user_skills_root" 2>/dev/null || true
    rm -rf "$staged_user_skills_root"
  fi
}
trap cleanup_temp EXIT

if [[ -n "$skills_arg" ]]; then
  project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  project_skills_root="$project_root/.claude/skills"
  user_skills_root="${HOME:+$HOME/.claude/skills}"
  user_skills_root="${user_skills_root:-~/.claude/skills}"
  effective_user_skills_root=""

  if [[ -n "${HOME:-}" && -d "$HOME/.claude/skills" ]]; then
    staged_user_skills_root="$(mktemp -d "${TMPDIR:-/tmp}/delegate-to-gemini-skills.XXXXXXXX")"
    # A dangling symlink among the skills (a stale backup dir) makes cp exit
    # non-zero after copying everything else; that must not abort the run.
    cp -rL "$HOME/.claude/skills/." "$staged_user_skills_root/" 2>/dev/null || true
    chmod -R u+w "$staged_user_skills_root"
    effective_user_skills_root="$staged_user_skills_root"
  fi

  IFS=',' read -ra skill_names <<<"$skills_arg"
  skill_dirs=()
  missing_skills=()
  for name in "${skill_names[@]}"; do
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    [[ -z "$name" ]] && continue
    if [[ -d "$project_skills_root/$name" ]]; then
      skill_dirs+=("$project_skills_root/$name")
    elif [[ -n "$effective_user_skills_root" && -d "$effective_user_skills_root/$name" ]]; then
      skill_dirs+=("$effective_user_skills_root/$name")
    else
      missing_skills+=("$name")
    fi
  done

  if [[ ${#skill_dirs[@]} -eq 0 && ${#missing_skills[@]} -eq 0 ]]; then
    echo "error: no valid skill names found in '$skills_arg' (blank, or only commas/whitespace)" >&2
    exit 1
  fi

  if [[ ${#missing_skills[@]} -gt 0 ]]; then
    joined_missing="$(IFS=,; echo "${missing_skills[*]}")"
    echo "error: skill(s) '$joined_missing' not found in $project_skills_root or $user_skills_root" >&2
    exit 1
  fi

  [[ -d "$project_skills_root" ]] && extra_args+=(--add-dir "$project_skills_root")
  if [[ -n "$effective_user_skills_root" ]]; then
    extra_args+=(--add-dir "$effective_user_skills_root")
    skill_roots_desc="$project_skills_root and $effective_user_skills_root"
  else
    skill_roots_desc="$project_skills_root"
  fi

  skill_md_list="$(printf '%s/SKILL.md, ' "${skill_dirs[@]}")"
  skill_md_list="${skill_md_list%, }"
  task="Before doing anything else, read the following: $skill_md_list — and follow their instructions. They and any skills they reference by name live as sibling directories under $skill_roots_desc — read those too whenever one routes you to another. Then: $task"
fi

# Cheapest first; a rejected model ID moves on to the next one. An explicit
# DELEGATE_MODEL (an ID from `agy models`) is tried alone: a fallback to a
# different model would silently change what the caller asked for.
models=("gemini-3.8-flash-medium" "gemini-3.8-flash-low")
if [[ -n "${DELEGATE_MODEL:-}" ]]; then
  models=("$DELEGATE_MODEL")
fi

retry_max="$(numeric_env_or_default DELEGATE_RETRY_MAX 3)"
retry_base_delay="$(numeric_env_or_default DELEGATE_RETRY_BASE_DELAY 2)"

is_transient() {
  grep -qiE 'network|timeout|timed out|connection (refused|reset)|eai_again|econnrefused|econnreset|(^|[^0-9])5[0-9][0-9]([^0-9]|$)|server error|temporarily unavailable|rate limit|too many requests' <<<"$1"
}

is_auth_missing() {
  grep -qi 'authentication required' <<<"$1"
}

is_quota_exhausted() {
  grep -qiE 'quota|resource.exhausted|insufficient.*credit|credit.*(exhausted|exceeded)|usage limit' <<<"$1"
}

# Records one call. $1 outcome, $2 exit code; reads the model, attempt count
# and envelope the last call left behind.
record_call() {
  telemetry_enabled || return 0
  telemetry_finish "$1" "$2" "$model" "$call_attempts" "$profile" "$skills_arg" "${envelope:-}" || true
}

# $1 the denied tool (agy's own name: command, write_file, ...), $2 agy's
# output to show. A denied tool exits 0 with an empty answer, which a caller
# would read as a finished task, so fail with the profile that allows it.
report_denied() {
  local tool="$1" shown="$2" needed
  case "$tool" in
    command) needed="write-shell (run it in a worktree)" ;;
    write_file) needed="write-workdir" ;;
    *) needed="a wider profile, or run from the repo that holds the files" ;;
  esac
  echo "error: agy auto-denied a '${tool:-unknown}' tool under profile '$profile'; the task needs $needed:" >&2
  printf '%s\n' "$shown" >&2
}

err_file="$(mktemp "${TMPDIR:-/tmp}/delegate-to-gemini-err.XXXXXXXX")"

# Sets $call_output (agy's stdout), $call_err (its stderr; empty in text mode,
# where stderr is merged into $call_output) and $call_attempts. Returns 0 on
# success, 1 on a non-transient failure, 2 if retries were exhausted on a
# transient one.
call_agy() {
  local model="$1"
  call_attempts=0
  while :; do
    call_attempts=$((call_attempts + 1))
    if (( use_json )); then
      if call_output="$("${trace_env[@]}" agy -p "$task" --model "$model" --print-timeout "${DELEGATE_PRINT_TIMEOUT:-15m}" \
        --output-format json "${effort_args[@]}" "${profile_args[@]}" "${extra_args[@]}" 2>"$err_file")"; then
        call_err="$(<"$err_file")"
        return 0
      fi
      call_err="$(<"$err_file")"
    else
      if call_output="$("${trace_env[@]}" agy -p "$task" --model "$model" --print-timeout "${DELEGATE_PRINT_TIMEOUT:-15m}" \
        "${effort_args[@]}" "${profile_args[@]}" "${extra_args[@]}" 2>&1)"; then
        call_err=""
        return 0
      fi
      call_err=""
    fi
    if ! is_transient "$call_output"$'\n'"$call_err"; then
      return 1
    fi
    if (( call_attempts >= retry_max )); then
      return 2
    fi
    sleep "$(( retry_base_delay * call_attempts ))"
  done
}

status=0
envelope=""
call_attempts=0
for model in "${models[@]}"; do
  status=0
  call_agy "$model" || status=$?

  if [[ $status -eq 0 ]]; then
    if (( use_json )) && jq -e . >/dev/null 2>&1 <<<"$call_output"; then
      envelope="$call_output"
      env_status="$(jq -r '.status // ""' <<<"$envelope")"
      denied_tool="$(jq -r '(.denied_actions // [])[0].action // empty' <<<"$envelope")"
      if [[ -n "$denied_tool" ]]; then
        report_denied "$denied_tool" "$call_err"
        record_call denied 3
        exit 3
      fi
      if [[ "$env_status" != "SUCCESS" ]]; then
        echo "error: agy finished with status '$env_status': $(jq -r '.error // ""' <<<"$envelope")" >&2
        printf '%s\n' "$call_err" >&2
        record_call error 1
        exit 1
      fi
      answer="$(jq -j '.response // ""' <<<"$envelope")"
      record_call success 0
      printf '%s\n' "$answer"
      exit 0
    fi

    # Text mode, or output that is not the JSON envelope: fall back to the
    # notice text for denial detection.
    if grep -q 'headless mode cannot prompt' <<<"$call_output"; then
      denied_tool=""
      if [[ "$call_output" =~ required\ the\ \"([a-z_]+)\"\ permission ]]; then
        denied_tool="${BASH_REMATCH[1]}"
      fi
      report_denied "$denied_tool" "$call_output"
      record_call denied 3
      exit 3
    fi
    record_call success 0
    printf '%s\n' "$call_output"
    exit 0
  fi

  # agy exits non-zero on an unknown model rather than falling back.
  if [[ $status -eq 1 ]] && grep -qF 'is not recognized as a known model' <<<"$call_output"$'\n'"$call_err"; then
    continue
  fi
  break
done

failure_text="$call_output"$'\n'"$call_err"
# On a failure agy prints a JSON envelope to stdout and the same message to
# stderr; show the message once instead of the raw envelope.
envelope_error=""
if (( use_json )); then
  envelope_error="$(jq -r '.error // empty' <<<"$call_output" 2>/dev/null)" || envelope_error=""
fi
if [[ -n "$envelope_error" ]]; then
  if [[ "$call_err" == *"$envelope_error"* ]]; then
    failure_text="$call_err"
  else
    failure_text="$envelope_error"$'\n'"$call_err"
  fi
fi
if [[ $status -eq 2 ]]; then
  echo "error: agy kept failing with a transient-looking error after $retry_max attempts (possible outage):" >&2
  outcome=transient_exhausted
elif is_auth_missing "$failure_text"; then
  echo "error: agy is not signed in — run 'agy' once interactively to authenticate:" >&2
  outcome=auth_missing
elif is_quota_exhausted "$failure_text"; then
  echo "error: agy reports exhausted quota/credits — wait for the reset, retrying won't help:" >&2
  outcome=quota
elif grep -qF 'is not recognized as a known model' <<<"$failure_text"; then
  outcome=model_rejected
else
  outcome=error
fi
printf '%s\n' "$failure_text" >&2
record_call "$outcome" 1
exit 1
