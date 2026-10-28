#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash git ripgrep gnugrep coreutils findutils
# shellcheck shell=bash
set -euo pipefail

# Output collections
FINDINGS_HIGH=()
FINDINGS_MEDIUM=()
FINDINGS_LOW=()

add_finding() {
    local sev="$1" target="$2" msg="$3"
    local entry
    entry="$(printf '%s\t%s\t%s' "$sev" "$target" "$msg")"
    case "$sev" in
        HIGH) FINDINGS_HIGH+=("$entry") ;;
        MEDIUM) FINDINGS_MEDIUM+=("$entry") ;;
        LOW) FINDINGS_LOW+=("$entry") ;;
    esac
}

find_primary_readme() {
    local repo="$1"
    local cand
    for cand in .github/README.md .github/README .github/README.rst README.md README README.rst docs/README.md docs/README docs/README.rst; do
        if [ -f "$repo/$cand" ]; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

get_doc_files() {
    local repo="$1"
    local r; r="$(find_primary_readme "$repo" || true)"
    if [ -n "$r" ] && [ -f "$repo/$r" ]; then
        echo "$repo/$r"
    fi
    if [ -d "$repo/docs" ]; then
        find "$repo/docs" -type f -name '*.md'
    fi
}

find_all_repo_md_files() {
    local repo="$1"
    find "$repo" -type d \( -name .git -o -name node_modules -o -name vendor -o -name target -o -name result \) -prune -o -type f -name '*.md' -print
}

readme_missing() {
    local repo="$1"
    if ! find_primary_readme "$repo" >/dev/null; then
        add_finding HIGH "README.md" "no README file found in root, .github/, or docs/"
    fi
}

readme_short() {
    local repo="$1"
    local r; r="$(find_primary_readme "$repo" || true)"
    [ -n "$r" ] || return 0
    local count
    count="$(wc -l < "$repo/$r" | tr -d ' ')"
    if [ "$count" -lt 10 ]; then
        add_finding MEDIUM "$r" "README has fewer than 10 lines ($count lines)"
    fi
}

readme_long() {
    local repo="$1"
    local r; r="$(find_primary_readme "$repo" || true)"
    [ -n "$r" ] || return 0
    local count
    count="$(wc -l < "$repo/$r" | tr -d ' ')"
    if [ "$count" -gt 500 ]; then
        add_finding LOW "$r" "README has more than 500 lines ($count lines)"
    fi
}

no_install_or_usage() {
    local repo="$1"
    local r; r="$(find_primary_readme "$repo" || true)"
    [ -n "$r" ] || return 0
    if ! grep -Eiq '^[#]+[[:space:]]+.*(install|quickstart|getting started|usage)' "$repo/$r"; then
        add_finding MEDIUM "$r" "no heading matching (install|quickstart|getting started|usage)"
    fi
}

no_license() {
    local repo="$1"
    if [ -f "$repo/LICENSE" ] || [ -f "$repo/LICENSE.md" ] || [ -f "$repo/COPYING" ]; then
        return 0
    fi
    local r; r="$(find_primary_readme "$repo" || true)"
    if [ -n "$r" ] && grep -Eiq '^[#]+[[:space:]]+.*license' "$repo/$r"; then
        return 0
    fi
    add_finding MEDIUM "${r:-LICENSE}" "no LICENSE/LICENSE.md/COPYING in root and no License heading in README"
}

many_badges() {
    local repo="$1"
    local r; r="$(find_primary_readme "$repo" || true)"
    [ -n "$r" ] || return 0
    local count
    count="$(grep -Eoi '!\[[^]]*\]\([^)]*(badge|shields\.io|badge\.svg)[^)]*\)|<img[^>]*(badge|shields\.io|badge\.svg)[^>]*>' "$repo/$r" | wc -l | tr -d ' ')"
    if [ "$count" -gt 5 ]; then
        add_finding LOW "$r" "more than 5 badge images in README ($count badges)"
    fi
}

fence_no_language() {
    local repo="$1"
    local file
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        local rel="${file#"$repo"/}"
        while IFS= read -r lineno; do
            [ -n "$lineno" ] || continue
            add_finding LOW "$rel:$lineno" "code fence opened with no language"
        done < <(awk '
        BEGIN { in_fence = 0; fence_char = ""; fence_len = 0; }
        {
            line = $0
            if (!in_fence) {
                if (match(line, /^[[:space:]]*(`{3,}|~{3,})/)) {
                    flen = RLENGTH
                    fchar = substr(line, RSTART, 1)
                    rest = substr(line, RSTART + flen)
                    gsub(/[[:space:]]/, "", rest)
                    if (length(rest) == 0) {
                        print NR
                    }
                    in_fence = 1
                    fence_char = fchar
                    fence_len = flen
                }
            } else {
                if (match(line, /^[[:space:]]*(`{3,}|~{3,})[[:space:]]*$/)) {
                    cchar = substr(line, RSTART, 1)
                    clen = RLENGTH
                    if (cchar == fence_char && clen >= fence_len) {
                        in_fence = 0
                    }
                }
            }
        }' "$file")
    done < <(get_doc_files "$repo")
}

image_no_alt() {
    local repo="$1"
    local file
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        local rel="${file#"$repo"/}"
        while IFS=$'\t' read -r lineno msg; do
            [ -n "$lineno" ] || continue
            add_finding MEDIUM "$rel:$lineno" "$msg"
        done < <(awk '
        {
            if ($0 ~ /!\[[[:space:]]*\]\(/) {
                print NR "\tmarkdown image with empty alt text"
            } else if (tolower($0) ~ /<img[[:space:]]/ && tolower($0) !~ /alt=/) {
                print NR "\t<img> tag without alt attribute"
            }
        }' "$file")
    done < <(get_doc_files "$repo")
}

bad_link_text() {
    local repo="$1"
    local file
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        local rel="${file#"$repo"/}"
        while IFS=: read -r lineno _; do
            [ -n "$lineno" ] || continue
            add_finding LOW "$rel:$lineno" "uninformative link text (e.g. here, click here, link, this)"
        done < <(grep -Eni '\[[[:space:]]*(here|click here|link|this)[[:space:]]*\]\(' "$file" || true)
    done < <(get_doc_files "$repo")
}

broken_relative_link() {
    local repo="$1"
    local file
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        local rel="${file#"$repo"/}"
        local fdir; fdir="$(dirname "$file")"
        while IFS=$'\t' read -r lineno target; do
            [ -n "$lineno" ] || continue
            case "$target" in
                http://*|https://*|mailto:*|\#*) continue ;;
            esac
            target="${target%% *}"
            local clean="${target%%#*}"
            clean="${clean%%\?*}"
            [ -n "$clean" ] || continue
            local dest
            if [[ "$clean" == /* ]]; then
                dest="$repo$clean"
            else
                dest="$fdir/$clean"
            fi
            if [ ! -e "$dest" ]; then
                add_finding HIGH "$rel:$lineno" "broken relative link: $target"
            fi
        done < <(awk '
        /^[ \t]*(```|~~~)/ { infence = !infence; next }
        infence { next }
        {
            str = $0
            gsub(/`[^`]*`/, "", str)
            while (match(str, /\[[^]]*\]\([^)]+\)/)) {
                m = substr(str, RSTART, RLENGTH)
                sub(/^[^\(]*\(/, "", m)
                sub(/\)$/, "", m)
                print NR "\t" m
                str = substr(str, RSTART + RLENGTH)
            }
        }' "$file")
    done < <(find_all_repo_md_files "$repo")
}

orphan_doc() {
    local repo="$1"
    [ -d "$repo/docs" ] || return 0
    declare -A visited=()
    local queue=()
    local r; r="$(find_primary_readme "$repo" || true)"
    if [ -n "$r" ] && [ -f "$repo/$r" ]; then
        local rpath; rpath="$(realpath "$repo/$r")"
        visited["$rpath"]=1
        queue+=("$rpath")
    fi
    if [ -f "$repo/docs/README.md" ]; then
        local dpath; dpath="$(realpath "$repo/docs/README.md")"
        if [ -z "${visited["$dpath"]:-}" ]; then
            visited["$dpath"]=1
            queue+=("$dpath")
        fi
    fi
    while [ "${#queue[@]}" -gt 0 ]; do
        local curr="${queue[0]}"
        queue=("${queue[@]:1}")
        local cdir; cdir="$(dirname "$curr")"
        while IFS=$'\t' read -r _ target; do
            case "$target" in http://*|https://*|mailto:*|\#*) continue ;; esac
            target="${target%% *}"
            local clean="${target%%#*}"
            clean="${clean%%\?*}"
            [ -n "$clean" ] || continue
            local dest
            if [[ "$clean" == /* ]]; then dest="$repo$clean"; else dest="$cdir/$clean"; fi
            if [ -f "$dest" ]; then
                local real_dest; real_dest="$(realpath "$dest")"
                if [[ "$real_dest" == "$repo"* ]] && [[ "$real_dest" == *.md ]]; then
                    if [ -z "${visited["$real_dest"]:-}" ]; then
                        visited["$real_dest"]=1
                        queue+=("$real_dest")
                    fi
                fi
            fi
        done < <(awk '{
            str = $0
            while (match(str, /\[[^]]*\]\([^)]+\)/)) {
                m = substr(str, RSTART, RLENGTH)
                sub(/^[^\(]*\(/, "", m)
                sub(/\)$/, "", m)
                print NR "\t" m
                str = substr(str, RSTART + RLENGTH)
            }
        }' "$curr")
    done

    local doc
    while IFS= read -r doc; do
        [ -f "$doc" ] || continue
        [ "$(basename "$doc")" = "README.md" ] && continue
        local rdoc; rdoc="$(realpath "$doc")"
        if [ -z "${visited["$rdoc"]:-}" ]; then
            local rel="${doc#"$repo"/}"
            add_finding MEDIUM "$rel" "orphan doc not reachable from README"
        fi
    done < <(find "$repo/docs" -type f -name '*.md')
}

docs_dir_no_index() {
    local repo="$1"
    [ -d "$repo/docs" ] || return 0
    local count
    count="$(find "$repo/docs" -type f -name '*.md' | wc -l | tr -d ' ')"
    [ "$count" -ge 3 ] || return 0
    [ ! -f "$repo/docs/README.md" ] || return 0
    local r; r="$(find_primary_readme "$repo" || true)"
    if [ -n "$r" ] && grep -Eq '\[[^]]*\]\([^)]*docs/[^)]*\)' "$repo/$r"; then
        return 0
    fi
    add_finding LOW "docs" "docs/ has 3+ markdown files but no docs/README.md and root README does not link into docs/"
}

missing_community_files() {
    local repo="$1"
    local files=(CONTRIBUTING.md SECURITY.md CHANGELOG.md)
    local f
    for f in "${files[@]}"; do
        if [ "$f" = "CHANGELOG.md" ]; then
            local tags=""
            if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                tags="$(git -C "$repo" tag 2>/dev/null || true)"
            fi
            [ -n "$tags" ] || continue
        fi
        if [ ! -f "$repo/$f" ] && [ ! -f "$repo/.github/$f" ] && [ ! -f "$repo/docs/$f" ]; then
            add_finding LOW "$f" "missing $f in root, .github/, or docs/"
        fi
    done
}

placeholder_text() {
    local repo="$1"
    local file
    while IFS= read -r file; do
        [ -f "$file" ] || continue
        local rel="${file#"$repo"/}"
        while IFS=: read -r lineno text; do
            [ -n "$lineno" ] || continue
            add_finding LOW "$rel:$lineno" "placeholder text found: $text"
        done < <(grep -En '(\b(TODO|TBD|FIXME)\b|[Ll]orem [Ii]psum|[Cc]oming [Ss]oon)' "$file" || true)
    done < <(get_doc_files "$repo")
}

agent_file_duplication() {
    local repo="$1"
    local c="$repo/CLAUDE.md"
    local a="$repo/AGENTS.md"
    if [ -f "$c" ] && [ -f "$a" ]; then
        local is_symlink=0
        if [ -L "$c" ] || [ -L "$a" ]; then
            local rc; rc="$(realpath "$c" 2>/dev/null || true)"
            local ra; ra="$(realpath "$a" 2>/dev/null || true)"
            [ "$rc" = "$ra" ] && is_symlink=1
        fi
        if [ "$is_symlink" -eq 0 ]; then
            local c_import=0 a_import=0
            grep -Eq '^[[:space:]]*@AGENTS\.md' "$c" && c_import=1
            grep -Eq '^[[:space:]]*@CLAUDE\.md' "$a" && a_import=1
            if [ "$c_import" -eq 0 ] && [ "$a_import" -eq 0 ]; then
                add_finding MEDIUM "CLAUDE.md" "both CLAUDE.md and AGENTS.md exist without import; import one from the other per agent-files.md"
            fi
        fi
    fi
    local f
    for f in CLAUDE.md AGENTS.md; do
        if [ -f "$repo/$f" ]; then
            local lines
            lines="$(wc -l < "$repo/$f" | tr -d ' ')"
            if [ "$lines" -gt 200 ]; then
                add_finding LOW "$f" "$f exceeds 200 lines ($lines lines)"
            fi
        fi
    done
}

readme_no_docs_link() {
    local repo="$1"
    [ -d "$repo/docs" ] || return 0
    local doc_count
    doc_count="$(find "$repo/docs" -type f -name '*.md' | wc -l | tr -d ' ')"
    [ "$doc_count" -gt 0 ] || return 0
    local r; r="$(find_primary_readme "$repo" || true)"
    [ -n "$r" ] || return 0
    if ! grep -q 'docs/' "$repo/$r"; then
        add_finding LOW "$r" "docs/ has markdown files but README never mentions docs/"
    fi
}

main() {
    local repo="${1:-.}"
    if [ "$#" -gt 1 ] || [ ! -d "$repo" ]; then
        echo "usage: check.sh [repo-path]" >&2
        exit 2
    fi

    repo="$(realpath "$repo")"

    FINDINGS_HIGH=()
    FINDINGS_MEDIUM=()
    FINDINGS_LOW=()

    readme_missing "$repo"
    readme_short "$repo"
    readme_long "$repo"
    no_install_or_usage "$repo"
    no_license "$repo"
    many_badges "$repo"
    fence_no_language "$repo"
    image_no_alt "$repo"
    bad_link_text "$repo"
    broken_relative_link "$repo"
    orphan_doc "$repo"
    docs_dir_no_index "$repo"
    missing_community_files "$repo"
    placeholder_text "$repo"
    agent_file_duplication "$repo"
    readme_no_docs_link "$repo"

    local item
    for item in "${FINDINGS_HIGH[@]}"; do
        printf '%s\n' "$item"
    done
    for item in "${FINDINGS_MEDIUM[@]}"; do
        printf '%s\n' "$item"
    done
    for item in "${FINDINGS_LOW[@]}"; do
        printf '%s\n' "$item"
    done

    local total=$((${#FINDINGS_HIGH[@]} + ${#FINDINGS_MEDIUM[@]} + ${#FINDINGS_LOW[@]}))
    printf '%d findings\n' "$total"
    exit 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
