#!/usr/bin/env bash
# Usage: eval-triggers.sh [--min PERCENT] [--max-false-fire PERCENT] [SKILLS_DIR]
# Measures whether an LLM router routes each trigger phrase to the right
# skill judged from SKILL.md descriptions alone. A "fire" phrase must route
# to its skill; a "not_fire" phrase (a near miss owned by a sibling) must
# route anywhere else. The two are scored apart: "top-1" is the fire hit
# rate (gated by --min), "false-fire" the share of not_fire phrases routed
# to their own skill (gated by --max-false-fire). Opt-in; spends Gemini quota.
set -euo pipefail

readonly DEFAULT_PROFILE="read"

usage() {
    echo "Usage: eval-triggers.sh [--min PERCENT] [--max-false-fire PERCENT] [SKILLS_DIR]" >&2
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
max_false_fire=""
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
        --max-false-fire)
            if [[ $# -lt 2 ]]; then
                usage
                exit 1
            fi
            max_false_fire="$2"
            shift 2
            ;;
        --max-false-fire=*)
            max_false_fire="${1#*=}"
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

for pct in "$min_percent" "$max_false_fire"; do
    [[ -n "$pct" ]] || continue
    if ! [[ "${pct%%%}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        usage
        exit 1
    fi
done

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

        # not_fire: near-miss phrases that belong to a sibling skill. Any
        # route except this skill passes; "!" marks the expectation.
        while IFS= read -r phrase; do
            [[ -n "$phrase" ]] || continue
            phrases+=("$phrase")
            phrase_expected+=("!$skill")
            skill_total["$skill"]=$((skill_total["$skill"] + 1))
            has_phrases=1
        done < <(jq -r '.not_fire // [] | .[]' "$triggers")

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

fire_total=0
fire_correct=0
nf_total=0
nf_fired=0
for ((i = 0; i < total_phrases; i++)); do
    expected="${phrase_expected[i]}"
    phrase="${phrases[i]}"
    got="${routed[i]}"

    if [[ "$expected" == !* ]]; then
        owner="${expected#!}"
        nf_total=$((nf_total + 1))
        if [[ "$got" != "$owner" ]]; then
            skill_correct["$owner"]=$((skill_correct["$owner"] + 1))
        else
            nf_fired=$((nf_fired + 1))
            skill_misses["$owner"]=$((skill_misses["$owner"] + 1))
            printf 'FALSE FIRE %s: "%s"\n' "$owner" "$phrase"
        fi
        continue
    fi
    fire_total=$((fire_total + 1))
    if [[ "$expected" == "$got" ]]; then
        skill_correct["$expected"]=$((skill_correct["$expected"] + 1))
        fire_correct=$((fire_correct + 1))
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

# percent X N IF_EMPTY: X as a share of N to one decimal, IF_EMPTY when N is 0.
percent() {
    awk -v x="$1" -v n="$2" -v e="$3" 'BEGIN { if (n == 0) printf "%s", e; else printf "%.1f", (x * 100.0 / n) }'
}

P="$(percent "$fire_correct" "$fire_total" 100.0)"
printf 'top-1: %d/%d (%s%%)\n' "$fire_correct" "$fire_total" "$P"
F="$(percent "$nf_fired" "$nf_total" 0.0)"
if ((nf_total > 0)); then
    printf 'false-fire: %d/%d (%s%%)\n' "$nf_fired" "$nf_total" "$F"
fi

status=0
if [[ -n "$min_percent" ]] &&
    jq -e -n --argjson p "$P" --argjson min "${min_percent%%%}" '$p < $min' >/dev/null 2>&1; then
    status=1
fi
if [[ -n "$max_false_fire" ]] &&
    jq -e -n --argjson f "$F" --argjson max "${max_false_fire%%%}" '$f > $max' >/dev/null 2>&1; then
    status=1
fi

exit "$status"
