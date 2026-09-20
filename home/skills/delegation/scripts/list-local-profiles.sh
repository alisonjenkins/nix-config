#!/usr/bin/env bash
# Lists profiles declared in profiles.toml (see ../delegate-to-local.md),
# marking whichever one the state file says is active and whether that
# active one is actually still responding. Never loads or unloads
# anything — read-only.
set -euo pipefail

for bin in curl jq yq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: '$bin' not found on PATH (yq: mikefarah/yq, parses profiles.toml)." >&2
    exit 1
  fi
done

if [[ -n "${LOCAL_LLM_PROFILES_FILE:-}" ]]; then
  profiles_file="$LOCAL_LLM_PROFILES_FILE"
elif [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
  profiles_file="$XDG_CONFIG_HOME/delegate-to-local/profiles.toml"
elif [[ -n "${HOME:-}" ]]; then
  profiles_file="$HOME/.config/delegate-to-local/profiles.toml"
else
  echo "error: none of LOCAL_LLM_PROFILES_FILE, XDG_CONFIG_HOME, or HOME are set — can't tell where profiles.toml lives." >&2
  exit 1
fi

if [[ ! -f "$profiles_file" ]]; then
  echo "error: profiles file not found: $profiles_file — see ../delegate-to-local.md for its schema." >&2
  exit 1
fi

if ! profiles_json="$(yq -p toml -o json '.' "$profiles_file" 2>&1)"; then
  echo "error: $profiles_file is not valid TOML:" >&2
  echo "$profiles_json" >&2
  exit 1
fi

if [[ -n "${LOCAL_LLM_STATE_DIR:-}" ]]; then
  state_dir="$LOCAL_LLM_STATE_DIR"
elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
  state_dir="$XDG_CACHE_HOME/delegate-to-local"
elif [[ -n "${HOME:-}" ]]; then
  state_dir="$HOME/.cache/delegate-to-local"
else
  state_dir=""
fi
active_file="${state_dir:+$state_dir/active-profile.json}"

active_name=""
active_url=""
if [[ -n "$active_file" && -f "$active_file" ]] && active_json="$(jq -e . "$active_file" 2>/dev/null)"; then
  active_name="$(jq -r '.profile // empty' <<<"$active_json")"
  active_url="$(jq -r '.url // empty' <<<"$active_json")"
fi

reservation_note=""
reservation_file="${state_dir:+$state_dir/reservation.json}"
if [[ -n "$reservation_file" && -f "$reservation_file" ]] && reservation_json="$(jq -e . "$reservation_file" 2>/dev/null)"; then
  res_profile="$(jq -r '.profile // empty' <<<"$reservation_json")"
  # A reservation names the profile it protects — stale state after a
  # switch (the reservation file only gets cleared by a successful
  # switch/stop, per delegate-to-local.md) could otherwise leave a
  # reservation for a DIFFERENT, no-longer-active profile on disk, which
  # would misleadingly show up against whatever profile is active now.
  if [[ -n "$active_name" && "$res_profile" == "$active_name" ]]; then
    res_expires="$(jq -r '.expires_at // 0' <<<"$reservation_json")"
    res_now="$(date +%s)"
    if [[ "$res_expires" =~ ^[0-9]+$ ]] && ((res_expires > res_now)); then
      res_reason="$(jq -r '.reason // "no reason given"' <<<"$reservation_json")"
      reservation_note=" — reserved ~$((res_expires - res_now))s more ($res_reason)"
    fi
  fi
fi

while IFS=$'\t' read -r name model description; do
  marker="  "
  status=""
  if [[ "$name" == "$active_name" ]]; then
    marker="* "
    if [[ -n "$active_url" ]] && curl -sS --max-time 1 "$active_url/v1/models" >/dev/null 2>&1; then
      status=" (active, responding$reservation_note)"
    else
      status=" (active, but not responding — it may have crashed)"
    fi
  fi
  printf '%s%s\t%s%s\t%s\n' "$marker" "$name" "$model" "$status" "$description"
done < <(jq -r 'to_entries[] | [.key, (.value.model // "?"), (.value.description // "")] | @tsv' <<<"$profiles_json")
