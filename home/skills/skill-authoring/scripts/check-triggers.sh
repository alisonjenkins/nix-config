#!/usr/bin/env bash
# Vocabulary gate for skill descriptions. Each skill may keep a triggers.json
# beside its SKILL.md: {"fire": ["a phrase a user would type", ...]}. Every
# phrase must share at least one content word with the text the always-loaded
# listing shows for that skill, so a rewrite that drops the words users type
# fails here. Model-free; it does not prove the model fires the skill, only
# that the words are still there.
#
# The listing text is worked out the way skill-transform does it at install
# (scripts/retrieval-eval/src/skill_transform.rs): the skill's summary when it
# has one, else the whole description when it fits, else its first sentence,
# cut at a word within LISTING_CHARS.
# Usage: check-triggers.sh [skills_dir]. Needs yq-go and jq on PATH.
# Prints one "FAIL <skill>: <phrase>" line per orphan phrase; exits 1 if any.
set -euo pipefail

# Words too common to count as shared vocabulary.
readonly STOPWORDS=' the and but not for are was you our all any may its can how why who this that with from have what when where which there their about into your then than them they will would could should please just need want help make does done like also been being here some more still after before again once '
# "aws", "nix" and "git" are three letters and carry the most signal.
readonly MIN_WORD_CHARS=3
readonly MIN_STEM_CHARS=3
# Default of modules.memoryRecall.skills.shortListing.chars.
readonly LISTING_CHARS="${LISTING_CHARS:-160}"

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

# Text up to and including the first full stop that ends the text or is
# followed by whitespace, so "v1.2" does not end a sentence.
first_sentence() {
    local text="$1" i
    for ((i = 0; i < ${#text}; i++)); do
        if [[ "${text:i:1}" == . ]] && { ((i + 1 == ${#text})) || [[ "${text:i+1:1}" == [[:space:]] ]]; }; then
            echo "${text:0:i+1}"
            return
        fi
    done
    echo "$text"
}

# Text cut to max chars at the last whitespace, as the listing shows it.
cut_at_word() {
    local text="$1" max="$2" head
    if ((${#text} <= max)); then
        echo "$text"
        return
    fi
    head="${text:0:max}"
    echo "${head%[[:space:]]*}"
}

listing_text() {
    local skill_md="$1" summary description
    summary="$(yq --front-matter=extract '.summary // .metadata.summary // ""' "$skill_md")"
    description="$(yq --front-matter=extract '.description // ""' "$skill_md")"
    if [[ -n "$summary" ]]; then
        cut_at_word "$summary" "$LISTING_CHARS"
    elif ((${#description} <= LISTING_CHARS)); then
        echo "$description"
    else
        cut_at_word "$(first_sentence "$description")" "$LISTING_CHARS"
    fi
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
    listing_stems="$(stems_of_text "$(listing_text "${skill_path}/SKILL.md")")"
    while IFS= read -r phrase; do
        checked=$((checked + 1))
        found=0
        while IFS= read -r word; do
            if grep -qxF -- "$(stem_of "$word")" <<<"$listing_stems"; then
                found=1
                break
            fi
        done < <(content_words "$phrase")
        if ((found == 0)); then
            echo "FAIL ${skill}: no word of \"${phrase}\" appears in the listed summary"
            failures=$((failures + 1))
        fi
    done < <(jq -r '.fire[]' "$triggers")
done

if ((failures > 0)); then
    echo "${failures} trigger phrase(s) with no vocabulary in their skill's listed summary" >&2
    exit 1
fi
echo "all ${checked} trigger phrases share vocabulary with their skill's listed summary"
