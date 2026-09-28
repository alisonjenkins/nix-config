#!/usr/bin/env bash
# Parses every shared skill's frontmatter with a strict YAML parser (yq-go).
# Claude Code tolerates an unquoted ": " inside a plain scalar; GitHub Copilot
# CLI and other strict parsers reject it and silently drop the skill. Fails if
# any home/skills/*/SKILL.md would not load everywhere it is linked (see
# home/programs/agent-skills). Needs yq-go on PATH.
set -euo pipefail

skills_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/home/skills"
failures=0

for skill in "${skills_dir}"/*/SKILL.md; do
    dir_name="$(basename "$(dirname "${skill}")")"
    rel="home/skills/${dir_name}/SKILL.md"
    if [[ "$(head -n 1 "${skill}")" != "---" ]]; then
        echo "FAIL ${rel}: no frontmatter block at the top"
        failures=$((failures + 1))
        continue
    fi
    if ! parsed="$(yq --front-matter=extract '[.name, (.description | type), (.description // "" | length)] | join("|")' "${skill}" 2>&1)"; then
        echo "FAIL ${rel}: invalid YAML: ${parsed}"
        failures=$((failures + 1))
        continue
    fi
    IFS='|' read -r name description_type description_length <<<"${parsed}"
    if [[ "${name}" != "${dir_name}" ]]; then
        echo "FAIL ${rel}: name '${name}' does not match directory '${dir_name}'"
        failures=$((failures + 1))
    fi
    if [[ "${description_type}" != "!!str" || "${description_length}" -eq 0 ]]; then
        echo "FAIL ${rel}: description is missing or not a string"
        failures=$((failures + 1))
    fi
done

if ((failures > 0)); then
    echo "${failures} skill frontmatter problem(s) that strict YAML parsers reject"
    exit 1
fi
echo "all skill frontmatter parses"
