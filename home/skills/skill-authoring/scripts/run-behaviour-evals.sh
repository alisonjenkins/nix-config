#!/usr/bin/env bash
# Usage: run-behaviour-evals.sh [--check] [--evals DIR] [--skills DIR] [SKILL...] [-- EVAL_ARGS...]
# Behaviour evals: does a skill's body change what Claude does? Each case in
# EVALS_DIR/<skill>/<case>/ (prompt.md + graders/*.md) runs through
# `claude plugin eval` against a throwaway plugin holding only that skill, so
# the with-without ablation compares "this skill loaded" with "nothing loaded".
# --check validates the case files offline and spends nothing. A live run
# spends Claude credits, capped per skill at $SKILL_EVALS_MAX_COST_USD (default
# 1) unless --max-cost-usd is passed after `--`.
set -euo pipefail

readonly CASE_KEYS="schema_version name description tags plugins runs expected_outcome model max_turns timeout_seconds allowed_tools disallowed_tools append_system_prompt env"
readonly GRADER_TYPES="regex tool_used tool_order file_exists llm baseline"

usage() {
    echo "Usage: run-behaviour-evals.sh [--check] [--evals DIR] [--skills DIR] [SKILL...] [-- EVAL_ARGS...]" >&2
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skills_dir="$(cd "$script_dir/../.." && pwd)"
evals_dir="$skills_dir/../skill-evals"
check_only=0
selected=()
eval_args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) check_only=1; shift ;;
        --evals) [[ $# -ge 2 ]] || { usage; exit 1; }; evals_dir="$2"; shift 2 ;;
        --skills) [[ $# -ge 2 ]] || { usage; exit 1; }; skills_dir="$2"; shift 2 ;;
        --) shift; eval_args=("$@"); break ;;
        -*) usage; exit 1 ;;
        *) selected+=("$1"); shift ;;
    esac
done

if [[ ! -d "$evals_dir" ]]; then
    echo "error: no evals dir at $evals_dir" >&2
    exit 1
fi

if ((${#selected[@]} == 0)); then
    for d in "$evals_dir"/*/; do
        [[ -d "$d" ]] && selected+=("$(basename "$d")")
    done
fi

errors=0
fail() {
    printf 'FAIL %s\n' "$1"
    errors=$((errors + 1))
}

check_case() {
    local skill="$1" case_dir="$2" case_name key type graders=0
    case_name="$skill/$(basename "$case_dir")"
    if [[ ! -f "$case_dir/prompt.md" ]]; then
        fail "$case_name: no prompt.md"
        return
    fi
    if ! keys="$(yq --front-matter=extract 'keys | .[]' "$case_dir/prompt.md" 2>/dev/null)"; then
        fail "$case_name: prompt.md frontmatter does not parse"
        return
    fi
    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        [[ " $CASE_KEYS " == *" $key "* ]] || fail "$case_name: unknown prompt.md key '$key'"
    done <<<"$keys"
    if [[ -z "$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$case_dir/prompt.md" | tr -d '[:space:]')" ]]; then
        fail "$case_name: prompt.md has no prompt body"
    fi
    for g in "$case_dir"/graders/*.md; do
        [[ -e "$g" ]] || continue
        graders=$((graders + 1))
        if ! type="$(yq --front-matter=extract '.type // ""' "$g" 2>/dev/null)"; then
            fail "$case_name: $(basename "$g") frontmatter does not parse"
            continue
        fi
        [[ " $GRADER_TYPES " == *" $type "* ]] || fail "$case_name: $(basename "$g") has unknown type '$type'"
    done
    ((graders > 0)) || fail "$case_name: no graders/*.md"
}

for skill in "${selected[@]}"; do
    if [[ ! -f "$skills_dir/$skill/SKILL.md" ]]; then
        fail "$skill: no skill at $skills_dir/$skill"
        continue
    fi
    found=0
    for case_dir in "$evals_dir/$skill"/*/; do
        [[ -d "$case_dir" ]] || continue
        found=1
        check_case "$skill" "${case_dir%/}"
    done
    ((found)) || fail "$skill: no cases in $evals_dir/$skill"
done

if ((errors > 0)); then
    exit 1
fi
if ((check_only)); then
    printf 'ok: %d skill(s) checked\n' "${#selected[@]}"
    exit 0
fi

out_dir="${SKILL_EVALS_OUT:-$PWD/skill-eval-results}"
mkdir -p "$out_dir"
work="$(mktemp -d "${TMPDIR:-/tmp}/skill-evals.XXXXXXXX")"
# shellcheck disable=SC2329 # invoked indirectly via trap
cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT

# A live run without a ceiling can spend without bound; default one in.
has_ceiling=0
for arg in "${eval_args[@]}"; do
    [[ "$arg" == --max-cost-usd || "$arg" == --max-cost-usd=* ]] && has_ceiling=1
done
if ((!has_ceiling)); then
    eval_args+=(--max-cost-usd "${SKILL_EVALS_MAX_COST_USD:-1}")
fi

status=0
for skill in "${selected[@]}"; do
    plugin="$work/$skill"
    mkdir -p "$plugin/.claude-plugin" "$plugin/skills"
    printf '{"name":"skill-eval-%s","version":"0.0.0","description":"Behaviour evals for the %s skill"}\n' "$skill" "$skill" >"$plugin/.claude-plugin/plugin.json"
    cp -R "$skills_dir/$skill" "$plugin/skills/$skill"
    cp -R "$evals_dir/$skill" "$plugin/evals"
    # Copies from the Nix store are read-only; make them removable.
    chmod -R u+w "$plugin"
    claude plugin eval "$plugin" --trust-plugin --no-publish \
        --model "${SKILL_EVALS_MODEL:-haiku}" \
        --json "$out_dir/$skill.json" \
        --report "$out_dir/$skill.html" \
        "${eval_args[@]}" || status=$?
done
exit "$status"
