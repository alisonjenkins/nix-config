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

# agy refuses to read outside the workspace, and ~/.claude/skills is
# home-manager-managed (symlinks into the read-only Nix store), which --add-dir
# does not make readable either. A dereferenced, user-owned copy does.
extra_args=()
staged_user_skills_root=""
# shellcheck disable=SC2329 # invoked indirectly via `trap`, below
cleanup_staged_skills() {
  [[ -n "$staged_user_skills_root" ]] || return 0
  chmod -R u+w "$staged_user_skills_root" 2>/dev/null || true
  rm -rf "$staged_user_skills_root"
}
trap cleanup_staged_skills EXIT

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

# Cheapest first; a rejected model ID moves on to the next one.
models=("gemini-3.8-flash-medium" "gemini-3.8-flash-low")

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

# Sets $call_output; returns 0 on success, 1 on a non-transient failure,
# 2 if retries were exhausted on a transient one.
call_agy() {
  local model="$1" attempt=1
  while :; do
    if call_output="$(agy -p "$task" --model "$model" --print-timeout "${DELEGATE_PRINT_TIMEOUT:-15m}" \
      "${effort_args[@]}" "${profile_args[@]}" "${extra_args[@]}" 2>&1)"; then
      return 0
    fi
    if ! is_transient "$call_output"; then
      return 1
    fi
    if (( attempt >= retry_max )); then
      return 2
    fi
    sleep "$(( retry_base_delay * attempt ))"
    attempt=$((attempt + 1))
  done
}

status=0
for model in "${models[@]}"; do
  status=0
  call_agy "$model" || status=$?

  if [[ $status -eq 0 ]]; then
    # A denied tool exits 0 with only a notice, which a caller would read as a
    # finished task. Fail with the profile that would have allowed it.
    if grep -q 'headless mode cannot prompt' <<<"$call_output"; then
      denied_tool=""
      if [[ "$call_output" =~ required\ the\ \"([a-z_]+)\"\ permission ]]; then
        denied_tool="${BASH_REMATCH[1]}"
      fi
      case "$denied_tool" in
        command) needed="write-shell (run it in a worktree)" ;;
        write_file) needed="write-workdir" ;;
        *) needed="a wider profile, or run from the repo that holds the files" ;;
      esac
      echo "error: agy auto-denied a '${denied_tool:-unknown}' tool under profile '$profile'; the task needs $needed:" >&2
      printf '%s\n' "$call_output" >&2
      exit 3
    fi
    printf '%s\n' "$call_output"
    exit 0
  fi

  # agy exits non-zero on an unknown model rather than falling back.
  if [[ $status -eq 1 ]] && grep -qF 'is not recognized as a known model' <<<"$call_output"; then
    continue
  fi
  break
done

if [[ $status -eq 2 ]]; then
  echo "error: agy kept failing with a transient-looking error after $retry_max attempts (possible outage):" >&2
elif is_auth_missing "$call_output"; then
  echo "error: agy is not signed in — run 'agy' once interactively to authenticate:" >&2
elif is_quota_exhausted "$call_output"; then
  echo "error: agy reports exhausted quota/credits — wait for the reset, retrying won't help:" >&2
fi
printf '%s\n' "$call_output" >&2
exit 1
