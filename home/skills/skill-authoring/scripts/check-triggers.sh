#!/usr/bin/env bash
# Vocabulary gate for skill descriptions. Each skill may keep a triggers.json
# beside its SKILL.md: {"fire": ["a phrase a user would type", ...]}. Every
# phrase must share at least one content word with that skill's description,
# so a rewrite that drops the words users type fails here. Model-free; it does
# not prove the model fires the skill, only that the words are still there.
# Usage: check-triggers.sh [skills_dir]. Needs yq-go and jq on PATH.
# Prints one "FAIL <skill>: <phrase>" line per orphan phrase; exits 1 if any.
set -euo pipefail

# Words too common to count as shared vocabulary.
readonly STOPWORDS=' the and but not for are was you our all any may its can how why who this that with from have what when where which there their about into your then than them they will would could should please just need want help make does done like also been being here some more still after before again once '
# "aws", "nix" and "git" are three letters and carry the most signal.
readonly MIN_WORD_CHARS=3
readonly MIN_STEM_CHARS=3

skills_dir="${1:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"}"
failures=0
checked=0

# Strips one common English suffix so "failing", "fails" and "failed" meet at
# "fail". Crude on purpose: it only has to be the same on both sides.
stem_of() {
    local word="$1" suffix stem
    for suffix in ing ed es s e; do
        if [[ "$suffix" == s && "$word" == *ss ]]; then
            continue
        fi
        if [[ "$word" == *"$suffix" ]] && ((${#word} - ${#suffix} >= MIN_STEM_CHARS)); then
            stem="${word%"$suffix"}"
            # "committing" -> "committ" -> "commit"; "press" and "call" keep their pair.
            if [[ "$suffix" == ing || "$suffix" == ed ]] && [[ "${stem: -1}" == "${stem: -2:1}" ]] && [[ "${stem: -1}" != [aeiouslzf] ]]; then
                stem="${stem%?}"
            fi
            echo "$stem"
            return
        fi
    done
    echo "$word"
}

content_words() {
    tr '[:upper:]' '[:lower:]' <<<"$1" | tr -cs '[:alnum:]_' '\n' | while IFS= read -r word; do
        if ((${#word} >= MIN_WORD_CHARS)) && [[ "$STOPWORDS" != *" ${word} "* ]]; then
            echo "$word"
        fi
    done
}

stems_of_text() {
    content_words "$1" | while IFS= read -r word; do
        stem_of "$word"
    done
}

for triggers in "$skills_dir"/*/triggers.json; do
    [[ -e "$triggers" ]] || continue
    skill_path="$(dirname "$triggers")"
    skill="$(basename "$skill_path")"
    description_stems="$(stems_of_text "$(yq --front-matter=extract '.description // ""' "${skill_path}/SKILL.md")")"
    while IFS= read -r phrase; do
        checked=$((checked + 1))
        found=0
        while IFS= read -r word; do
            if grep -qxF -- "$(stem_of "$word")" <<<"$description_stems"; then
                found=1
                break
            fi
        done < <(content_words "$phrase")
        if ((found == 0)); then
            echo "FAIL ${skill}: no word of \"${phrase}\" appears in the description"
            failures=$((failures + 1))
        fi
    done < <(jq -r '.fire[]' "$triggers")
done

if ((failures > 0)); then
    echo "${failures} trigger phrase(s) with no vocabulary in their skill's description" >&2
    exit 1
fi
echo "all ${checked} trigger phrases share vocabulary with their skill's description"
