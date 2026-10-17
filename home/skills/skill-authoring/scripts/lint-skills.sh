#!/usr/bin/env bash
# Model-free convention checks for shared skills (see ../conventions.md and
# ../frontmatter.md). Usage: lint-skills.sh [skills_dir]
# Defaults to the directory holding this skill. Needs yq-go on PATH.
# Prints one "FAIL <skill>: <reason>" line per problem; exits 1 if any.
set -euo pipefail

readonly MAX_DESCRIPTION_CHARS=1536 # Claude Code truncates a listing entry here
readonly MAX_BODY_LINES=500
# The six agentskills.io fields, plus the one extension frontmatter.md tolerates.
readonly ALLOWED_KEYS='["name","description","license","compatibility","metadata","allowed-tools","argument-hint"]'
# Split so this file does not match its own check.
readonly MACHINE_PATHS='(^|[^[:alnum:]_./-])(/run/current-''system|/ho''me/[a-z]|/Users/[a-z]|/nix/store/[a-z0-9]{32})'

skills_dir="${1:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"}"
failures=0

fail() {
    echo "FAIL $1: $2"
    failures=$((failures + 1))
}

lint_frontmatter() {
    local skill="$1" file="$2" length unknown
    length="$(yq --front-matter=extract '.description // "" | length' "$file")"
    if ((length > MAX_DESCRIPTION_CHARS)); then
        fail "$skill" "description is ${length} chars, over the ${MAX_DESCRIPTION_CHARS} the listing keeps"
    fi
    unknown="$(yq --front-matter=extract \
        "keys | map(select(. as \$k | ${ALLOWED_KEYS} | contains([\$k]) | not)) | join(\",\")" "$file")"
    if [[ -n "$unknown" ]]; then
        fail "$skill" "frontmatter field outside the agentskills.io spec: ${unknown}"
    fi
}

lint_body_length() {
    local skill="$1" file="$2" lines
    lines="$(wc -l <"$file")"
    if ((lines > MAX_BODY_LINES)); then
        fail "$skill" "SKILL.md is ${lines} lines, over ${MAX_BODY_LINES}; move detail into a sibling file"
    fi
}

# A link inside a fenced block or an inline code span is an example, not a link.
prose_only() {
    # shellcheck disable=SC2016 # the backticks are literal, for sed
    awk '/^```/ { fenced = !fenced; next } !fenced' "$1" | sed 's/`[^`]*`//g'
}

lint_links() {
    local skill="$1" skill_path="$2" md target path
    while IFS= read -r md; do
        while IFS= read -r target; do
            case "$target" in
                *://* | mailto:* | '#'* | /* | *' '* | *'<'* | *'*'*) continue ;;
            esac
            path="${target%%#*}"
            [[ -n "$path" ]] || continue
            if [[ ! -e "$(dirname "$md")/${path}" ]]; then
                fail "$skill" "${md#"${skill_path}"/} links to missing ${target}"
            fi
        done < <(prose_only "$md" | grep -oE '\]\([^)]+\)' | sed -e 's/^](//' -e 's/)$//' || true)
    done < <(find "$skill_path" -name '*.md' -type f | sort)
}

lint_script_paths() {
    local skill="$1" skill_path="$2" script hit
    while IFS= read -r script; do
        hit="$(grep -nE "$MACHINE_PATHS" "$script" || true)"
        if [[ -n "$hit" ]]; then
            fail "$skill" "${script#"${skill_path}"/} hardcodes a machine path: ${hit%%$'\n'*}"
        fi
    done < <(find "$skill_path" -type f \( -name '*.sh' -o -name '*.py' \) -not -path '*/tests/*' | sort)
}

for skill_path in "$skills_dir"/*/; do
    skill_path="${skill_path%/}"
    skill="$(basename "$skill_path")"
    file="${skill_path}/SKILL.md"
    if [[ ! -f "$file" ]]; then
        fail "$skill" "no SKILL.md"
        continue
    fi
    lint_frontmatter "$skill" "$file"
    lint_body_length "$skill" "$file"
    lint_links "$skill" "$skill_path"
    lint_script_paths "$skill" "$skill_path"
done

if ((failures > 0)); then
    echo "${failures} skill convention problem(s)" >&2
    exit 1
fi
echo "all skills pass the convention lint"
