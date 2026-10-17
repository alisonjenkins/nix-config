#!/usr/bin/env bash
# Usage: eval-triggers.sh [--min PERCENT] [SKILLS_DIR]
# Measures whether an LLM router routes each trigger phrase to the right
# skill judged from SKILL.md descriptions alone. Opt-in; spends Gemini quota.
set -euo pipefail

readonly DEFAULT_PROFILE="read"

usage() {
    echo "Usage: eval-triggers.sh [--min PERCENT] [SKILLS_DIR]" >&2
}

parse_reply() {
    local raw="$1" n="$2"
    jq -e -r -sR --argjson n "$n" '
      (
        (capture("```(?:json)?\\s*(?<fenced>\\[[\\s\\S]*?\\])\\s*```") | .fenced)
        //
        (capture("(?<json>\\[[\\s\\S]*\\])") | .json)
      )
      | fromjson
      | select(type == "array")
      | ($n as $count | [ .[] | select(.i != null and .skill != null) | {key: (.i | tostring), value: (.skill | tostring)} ] | from_entries) as $map
      | [ range(1; $n + 1) | (. | tostring) as $k | if $map[$k] == null then error("missing phrase \($k)") else $map[$k] end ]
      | .[]
    ' <<<"$raw"
}

min_percent=""
skills_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --min)
            if [[ $# -lt 2 ]]; then
                usage
                exit 1
            fi
            min_percent="$2"
            shift 2
            ;;
        --min=*)
            min_percent="${1#*=}"
            shift
            ;;
        -*)
            usage
            exit 1
            ;;
        *)
            if [[ -z "$skills_dir" ]]; then
                skills_dir="$1"
                shift
            else
                usage
                exit 1
            fi
            ;;
    esac
done

if [[ -n "$min_percent" ]]; then
    min_clean="${min_percent%%%}"
    if ! [[ "$min_clean" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        usage
        exit 1
    fi
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$skills_dir" ]]; then
    skills_dir="$(cd "$script_dir/../.." && pwd)"
fi

candidates=()
phrases=()
phrase_expected=()
skills_with_phrases=()

declare -A skill_total=()
declare -A skill_correct=()
declare -A skill_misses=()

for skill_md in "$skills_dir"/*/SKILL.md; do
    [[ -e "$skill_md" ]] || continue
    skill_dir="$(dirname "$skill_md")"
    skill="$(basename "$skill_dir")"
    description="$(yq --front-matter=extract '.description // ""' "$skill_md" | tr '\n' ' ')"
    description="${description%"${description##*[![:space:]]}"}"
    candidates+=("${skill}: ${description}")

    triggers="$skill_dir/triggers.json"
    if [[ -f "$triggers" ]]; then
        skill_total["$skill"]=0
        skill_correct["$skill"]=0
        skill_misses["$skill"]=0
        has_phrases=0

        while IFS= read -r phrase; do
            [[ -n "$phrase" ]] || continue
            phrases+=("$phrase")
            phrase_expected+=("$skill")
            skill_total["$skill"]=$((skill_total["$skill"] + 1))
            has_phrases=1
        done < <(jq -r '.fire // [] | .[]' "$triggers")

        if ((has_phrases)); then
            skills_with_phrases+=("$skill")
        fi
    fi
done

total_phrases="${#phrases[@]}"
if ((total_phrases == 0)); then
    printf 'top-1: 0/0 (100.0%%)\n'
    exit 0
fi

candidates_text=""
for c in "${candidates[@]}"; do
    candidates_text+="$c"$'\n'
done

phrases_text=""
for ((i = 0; i < total_phrases; i++)); do
    num=$((i + 1))
    phrases_text+="${num}. ${phrases[i]}"$'\n'
done

prompt="Skills:
$candidates_text
Phrases:
$phrases_text
For each numbered phrase say which ONE skill from the list a coding assistant should load first, judging only from the descriptions; answer with ONLY a JSON array of {\"i\": <number>, \"skill\": \"<name>\"} objects, no prose."

delegate="${EVAL_TRIGGERS_DELEGATE:-$script_dir/../../delegation/scripts/delegate-to-gemini.sh}"

err_file="$(mktemp "${TMPDIR:-/tmp}/eval-triggers-err.XXXXXXXX")"
# shellcheck disable=SC2329 # invoked indirectly via trap
cleanup() {
    rm -f "$err_file"
}
trap cleanup EXIT

delegate_status=0
reply="$(bash "$delegate" "$prompt" "$DEFAULT_PROFILE" 2>"$err_file")" || delegate_status=$?

if ((delegate_status != 0)); then
    cat "$err_file" >&2
    exit 2
fi

if ! parsed="$(parse_reply "$reply" "$total_phrases" 2>/dev/null)"; then
    echo "error: could not parse the router reply" >&2
    head -n 20 <<<"$reply" >&2
    exit 3
fi

mapfile -t routed <<<"$parsed"

total_correct=0
for ((i = 0; i < total_phrases; i++)); do
    expected="${phrase_expected[i]}"
    phrase="${phrases[i]}"
    got="${routed[i]}"

    if [[ "$expected" == "$got" ]]; then
        skill_correct["$expected"]=$((skill_correct["$expected"] + 1))
        total_correct=$((total_correct + 1))
    else
        skill_misses["$expected"]=$((skill_misses["$expected"] + 1))
        printf 'MISS %s: "%s" -> %s\n' "$expected" "$phrase" "$got"
    fi
done

for s in "${skills_with_phrases[@]}"; do
    if ((skill_misses["$s"] > 0)); then
        printf '%s: %d/%d\n' "$s" "${skill_correct["$s"]}" "${skill_total["$s"]}"
    fi
done

P="$(awk -v x="$total_correct" -v n="$total_phrases" 'BEGIN { printf "%.1f", (x * 100.0 / n) }')"
printf 'top-1: %d/%d (%s%%)\n' "$total_correct" "$total_phrases" "$P"

if [[ -n "$min_percent" ]]; then
    min_clean="${min_percent%%%}"
    if jq -e -n --argjson p "$P" --argjson min "$min_clean" '$p < $min' >/dev/null 2>&1; then
        exit 1
    fi
fi

exit 0
