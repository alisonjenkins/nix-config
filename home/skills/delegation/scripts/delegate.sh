#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <task> [profile] [skill[,skill...]]" >&2
  echo "valid profiles: read, write-workdir, write-and-test" >&2
  echo "skill: one or more comma-separated Claude skill names to hand to" >&2
  echo "  the delegate, each resolved from ./.claude/skills/<skill> then" >&2
  echo "  ~/.claude/skills/<skill>" >&2
}

if [[ $# -lt 1 || $# -gt 3 ]]; then
  usage
  exit 1
fi

if ! command -v copilot >/dev/null 2>&1; then
  echo "error: 'copilot' CLI not found on PATH — install the official GitHub Copilot CLI (npm install -g @github/copilot) and authenticate with 'copilot login' before using this skill." >&2
  exit 1
fi

# Credit/quota exhaustion is account-wide and doesn't clear until the
# billing period resets, so a fresh invocation re-discovering that by
# actually calling copilot is a wasted round trip every time. Cache it
# and skip straight to a one-line error, no copilot call, until the
# cooldown lapses. DELEGATE_CREDITS_COOLDOWN_SECONDS overrides the
# default 24h guess at the reset cadence; run reset-credits-cooldown.sh
# to clear it early (e.g. the account's limit got raised).
#
# credits_state_dir is empty (not "/.cache/...") when none of
# DELEGATE_STATE_DIR, XDG_CACHE_HOME, or HOME are set — gate on that,
# not specifically on HOME, so an explicit DELEGATE_STATE_DIR/
# XDG_CACHE_HOME still works in a HOME-less environment.
if [[ -n "${DELEGATE_STATE_DIR:-}" ]]; then
  credits_state_dir="$DELEGATE_STATE_DIR"
elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  credits_state_dir="$XDG_CACHE_HOME/delegate-to-copilot"
elif [[ -n "${HOME:-}" ]]; then
  credits_state_dir="$HOME/.cache/delegate-to-copilot"
else
  credits_state_dir=""
fi
credits_cooldown_file="${credits_state_dir:+$credits_state_dir/credits-exhausted-until}"
credits_cooldown_seconds="${DELEGATE_CREDITS_COOLDOWN_SECONDS:-86400}"

if [[ -n "$credits_state_dir" && -f "$credits_cooldown_file" ]]; then
  cooldown_until="$(<"$credits_cooldown_file")"
  now="$(date +%s)"
  if [[ "$cooldown_until" =~ ^[0-9]+$ ]] && (( now < cooldown_until )); then
    until_human="$(date -d "@$cooldown_until" -Iseconds 2>/dev/null || date -r "$cooldown_until" 2>/dev/null || echo "$cooldown_until")"
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "error: copilot credits were reported exhausted on the last attempt; skipping until $until_human without calling copilot. Run $script_dir/reset-credits-cooldown.sh to clear this early (e.g. if the limit got raised)." >&2
    exit 1
  fi
fi

task="$1"
profile="${2:-read}"
skills_arg="${3:-}"

case "$profile" in
  read)
    tool_scope="read"
    ;;
  write-workdir)
    tool_scope="read,write"
    ;;
  write-and-test)
    tool_scope="read,write,shell(npm test,pytest,cargo test)"
    ;;
  *)
    echo "error: invalid profile '$profile'" >&2
    echo "valid profiles: read, write-workdir, write-and-test" >&2
    exit 1
    ;;
esac

# One or more Claude skills (e.g. "programming,testing") are opt-in:
# resolve each's directory, grant the delegate read access, and tell it
# to read each SKILL.md first so it follows the same conventions this
# session does. --add-dir is what makes the referenced sub-files
# (languages/rust.md and friends) actually readable, not just the
# skill's existence known.
#
# Skills cross-reference each other by name ("invoke the design skill"),
# not by path, so even a named skill's own directory isn't enough — grant
# access to both skill roots (project and global) so any sibling skill
# any of them routes to is readable too.
#
# ~/.claude/skills is unreadable to the delegate even with --add-dir: it's
# home-manager-managed, so its files are symlinks into the Nix store,
# root-owned and mode 444, and Copilot refuses to read files it doesn't
# consider user-owned. `cp -rL` dereferences the symlinks into real,
# user-owned files in a throwaway staging dir instead; that dir is what
# actually gets granted and cleaned up on exit.
copilot_extra_args=()
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
  # A literal "~/..." here is for messages only when HOME is unset — never
  # dereferenced as a real path, since the staging step below is itself
  # HOME-gated.
  user_skills_root="${HOME:+$HOME/.claude/skills}"
  user_skills_root="${user_skills_root:-~/.claude/skills}"
  effective_user_skills_root=""

  if [[ -n "${HOME:-}" && -d "$HOME/.claude/skills" ]]; then
    staged_user_skills_root="$(mktemp -d "${TMPDIR:-/tmp}/delegate-to-copilot-skills.XXXXXXXX")"
    cp -rL "$HOME/.claude/skills/." "$staged_user_skills_root/"
    chmod -R u+w "$staged_user_skills_root"
    effective_user_skills_root="$staged_user_skills_root"
  fi

  IFS=',' read -ra skill_names <<<"$skills_arg"
  skill_dirs=()
  missing_skills=()
  for name in "${skill_names[@]}"; do
    if [[ -d "$project_skills_root/$name" ]]; then
      skill_dirs+=("$project_skills_root/$name")
    elif [[ -n "$effective_user_skills_root" && -d "$effective_user_skills_root/$name" ]]; then
      skill_dirs+=("$effective_user_skills_root/$name")
    else
      missing_skills+=("$name")
    fi
  done

  if [[ ${#missing_skills[@]} -gt 0 ]]; then
    joined_missing="$(IFS=,; echo "${missing_skills[*]}")"
    echo "error: skill(s) '$joined_missing' not found in $project_skills_root or $user_skills_root" >&2
    exit 1
  fi

  [[ -d "$project_skills_root" ]] && copilot_extra_args+=(--add-dir "$project_skills_root")
  [[ -n "$effective_user_skills_root" ]] && copilot_extra_args+=(--add-dir "$effective_user_skills_root")

  skill_md_list="$(printf '%s/SKILL.md, ' "${skill_dirs[@]}")"
  skill_md_list="${skill_md_list%, }"
  task="Before doing anything else, read the following: $skill_md_list — and follow their instructions. They and any skills they reference by name live as sibling directories under $project_skills_root and $effective_user_skills_root — read those too (e.g. their own SKILL.md and any files they route to) whenever one routes you to another. Then: $task"
fi

# gpt-5.6-luna is the preferred model: cheapest tier, when the account has
# it. Not every account/CLI version has it yet, so fall back to the next
# cheapest confirmed-available model (claude-haiku-4.5) on rejection.
preferred_model="gpt-5.6-luna"
fallback_model="claude-haiku-4.5"

# A Copilot outage looks like a network/server error, not a model rejection —
# retrying the same model with backoff is the right response, per this repo's
# tenacity mandate (retry transient failures before giving up).
retry_max="${DELEGATE_RETRY_MAX:-3}"
retry_base_delay="${DELEGATE_RETRY_BASE_DELAY:-2}"

is_transient() {
  # No \b: GNU grep treats it as a word boundary, but that's a GNU
  # extension, not POSIX ERE — this needs to work on whatever grep ships
  # with the invoking machine, including macOS's stock BSD grep. Match
  # the 3-digit status code flanked by non-digits instead.
  grep -qiE 'network|timeout|timed out|connection (refused|reset)|eai_again|econnrefused|econnreset|(^|[^0-9])5[0-9][0-9]([^0-9]|$)|server error|temporarily unavailable|rate limit|too many requests' <<<"$1"
}

# Credit/quota exhaustion is account-wide, not model- or server-specific:
# retrying or switching models both waste an attempt without fixing it.
is_credits_exhausted() {
  grep -qiE 'quota|premium request|insufficient.*(credit|balance)|credit.*(exhausted|exceeded)|budget.*exceeded|monthly limit|spending limit' <<<"$1"
}

# Runs copilot with the given model, retrying on transient failures.
# Sets $call_output; returns 0 on success, 1 on a non-transient failure
# (e.g. model rejection), 2 if retries were exhausted on a transient one.
call_copilot() {
  local model="$1" attempt=1
  while :; do
    if call_output="$(copilot -p "$task" --model "$model" -s --no-ask-user \
      --allow-tool="$tool_scope" "${copilot_extra_args[@]}" 2>&1)"; then
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
call_copilot "$preferred_model" || status=$?

if [[ $status -eq 0 ]]; then
  printf '%s\n' "$call_output"
  exit 0
fi

preferred_model_rejected="Model \"$preferred_model\" from --model flag is not available."
if [[ $status -eq 1 ]] && grep -qF "$preferred_model_rejected" <<<"$call_output"; then
  status=0
  call_copilot "$fallback_model" || status=$?
  if [[ $status -eq 0 ]]; then
    printf '%s\n' "$call_output"
    exit 0
  fi
fi

if [[ $status -eq 2 ]]; then
  echo "error: copilot CLI kept failing with a transient-looking error after $retry_max attempts (possible outage):" >&2
elif [[ $status -eq 1 ]] && is_credits_exhausted "$call_output"; then
  echo "error: copilot CLI reports exhausted credits/quota — top up or wait for the reset, retrying or switching models won't help:" >&2
  if [[ -n "$credits_state_dir" ]]; then
    mkdir -p "$credits_state_dir" 2>/dev/null &&
      echo "$(( $(date +%s) + credits_cooldown_seconds ))" >"$credits_cooldown_file" 2>/dev/null || true
  fi
fi
printf '%s\n' "$call_output" >&2
exit 1
