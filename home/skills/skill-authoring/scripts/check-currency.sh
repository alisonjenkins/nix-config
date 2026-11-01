#!/usr/bin/env bash
# Checks the guidance sources in ../guidance-sources.json (see ../currency.md).
# Usage: check-currency.sh [--registry FILE] [--today YYYY-MM-DD] [--offline]
# Prints INVALID / OVERDUE / FETCHFAIL / STALE lines on stdout, a summary on stderr.
# Exit 0 clean, 1 findings, 2 invalid registry. Needs curl and jq.
set -euo pipefail

registry="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/guidance-sources.json"
today="$(date -u +%Y-%m-%d)"
offline=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --registry)
            [[ $# -ge 2 ]] || { echo "error: --registry requires a file" >&2; exit 2; }
            registry="$2"
            shift 2
            ;;
        --today)
            [[ $# -ge 2 ]] || { echo "error: --today requires a date" >&2; exit 2; }
            today="$2"
            shift 2
            ;;
        --offline)
            offline=1
            shift
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [[ ! -f "$registry" ]]; then
    echo "error: registry file not found: $registry" >&2
    exit 2
fi

if ! jq empty "$registry" 2>/dev/null; then
    echo "INVALID <registry>: invalid JSON"
    exit 2
fi

# shellcheck disable=SC2016 # jq filter uses literal $ expressions
validate_filter='
  . as $root
  | ($root.max_review_days // {}) as $max_days
  | ($root.sources // []) as $sources
  | [
      (if ($root | has("max_review_days") | not) then "INVALID <registry>: missing max_review_days" else empty end),
      (if ($root | has("sources") | not) or (($sources | type) != "array") then "INVALID <registry>: missing sources array" else empty end),
      ($sources | map(.id // "") | group_by(.)[] | select(.[0] != "" and length > 1) | "INVALID \(.[0]): duplicate id"),
      ($sources[] | . as $s | ($s.id // "<unknown>") as $id | [
        (if ($s.id // "") == "" then "INVALID \($id): missing id" else empty end),
        (if ($s.class // "") == "" then "INVALID \($id): missing class"
         elif ($max_days | has($s.class) | not) then "INVALID \($id): class \"\($s.class)\" not in max_review_days"
         else empty end),
        (if ($s.url // "") == "" then "INVALID \($id): missing url" else empty end),
        (if ($s.tracks // "") == "" then "INVALID \($id): missing tracks" else empty end),
        (if (($s.feeds | type) != "array") or (($s.feeds | length) == 0) then "INVALID \($id): feeds must be a non-empty array" else empty end),
        (if (($s.expect | type) != "array") then "INVALID \($id): expect must be an array" else empty end),
        (if ($s.reviewed // "") == "" then "INVALID \($id): missing reviewed"
         elif (try ($s.reviewed | strptime("%Y-%m-%d") | mktime) catch null) == null then "INVALID \($id): invalid reviewed date \"\($s.reviewed)\""
         else empty end),
        (if ($s.review_by // "") == "" then "INVALID \($id): missing review_by"
         elif (try ($s.review_by | strptime("%Y-%m-%d") | mktime) catch null) == null then "INVALID \($id): invalid review_by date \"\($s.review_by)\""
         else empty end),
        (if ($s.review_note // "") == "" then "INVALID \($id): missing review_note" else empty end),
        (
          if ($max_days | has($s.class // "")) and
             ((try ($s.reviewed | strptime("%Y-%m-%d") | mktime) catch null) != null) and
             ((try ($s.review_by | strptime("%Y-%m-%d") | mktime) catch null) != null) then
            ($s.reviewed | strptime("%Y-%m-%d") | mktime) as $rev_ts
            | ($s.review_by | strptime("%Y-%m-%d") | mktime) as $by_ts
            | ($max_days[$s.class] * 86400) as $max_secs
            | if $by_ts > ($rev_ts + $max_secs) then
                "INVALID \($id): review_by (\($s.review_by)) exceeds max_review_days (\($max_days[$s.class]) days) from reviewed (\($s.reviewed))"
              else empty end
          else empty end
        )
      ][])
    ][]
'

invalid_lines="$(jq -r "$validate_filter" "$registry")"

registry_dir="$(dirname "$registry")"
missing_feed_lines=()
while IFS= read -r -d '' id && IFS= read -r -d '' feed; do
    if [[ ! -f "$registry_dir/$feed" ]]; then
        missing_feed_lines+=("INVALID ${id}: feeds entry \"${feed}\" is not a file next to the registry")
    fi
done < <(jq -j '.sources[]? | . as $s | ($s.id // "<unknown>") as $id | if (.feeds | type) == "array" then .feeds[] | "\($id)\u0000\(.)\u0000" else empty end' "$registry")

if [[ -n "$invalid_lines" || ${#missing_feed_lines[@]} -gt 0 ]]; then
    if [[ -n "$invalid_lines" ]]; then
        printf '%s\n' "$invalid_lines"
    fi
    if (( ${#missing_feed_lines[@]} > 0 )); then
        printf '%s\n' "${missing_feed_lines[@]}"
    fi
    exit 2
fi

fetch_url() {
    local url="$1"
    local attempt=0
    local max_retries=3
    local backoffs=(1 2 4)
    local sleep_base="${CURRENCY_RETRY_SLEEP:-1}"

    while true; do
        if curl -fsSL --max-time 30 "$url"; then
            return 0
        fi
        if (( attempt >= max_retries )); then
            return 1
        fi
        local delay=$(( backoffs[attempt] * sleep_base ))
        if (( delay > 0 )); then
            sleep "$delay"
        fi
        attempt=$((attempt + 1))
    done
}

checked=0
overdue=0
stale=0
fetchfail=0

while IFS= read -r source_json; do
    checked=$((checked + 1))
    id="$(jq -r '.id' <<< "$source_json")"
    review_by="$(jq -r '.review_by' <<< "$source_json")"
    url="$(jq -r '.url' <<< "$source_json")"
    feeds_joined="$(jq -r '.feeds | join(", ")' <<< "$source_json")"

    if [[ "$review_by" < "$today" ]]; then
        echo "OVERDUE ${id}: review_by ${review_by}"
        overdue=$((overdue + 1))
    fi

    if (( offline == 1 )); then
        continue
    fi

    body=""
    if ! body="$(fetch_url "$url")"; then
        echo "FETCHFAIL ${id}: ${url}"
        fetchfail=$((fetchfail + 1))
        continue
    fi

    while IFS= read -r -d '' expect_str; do
        # A here-string, not a pipe: grep -q exits early and pipefail would turn the SIGPIPE into a false STALE.
        if ! grep -F -q -- "$expect_str" <<< "$body"; then
            echo "STALE ${id}: missing \"${expect_str}\" (feeds: ${feeds_joined})"
            stale=$((stale + 1))
        fi
    done < <(jq -j '.expect[] | (., "\u0000")' <<< "$source_json")
done < <(jq -c '.sources[]' "$registry")

echo "checked=${checked} overdue=${overdue} stale=${stale} fetchfail=${fetchfail}" >&2

if (( overdue > 0 || stale > 0 || fetchfail > 0 )); then
    exit 1
fi
