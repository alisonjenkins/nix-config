#!/usr/bin/env bash
# Mutation testing for the shell scripts under home/skills. Changes one
# operator in a script at a time, runs that script's tests in a temporary copy
# of the skills tree, and reports mutants the tests did not catch. Results are
# cached in a baseline JSON file keyed by a content hash.
#
# Usage:
#   mutate-scripts.sh [--changed | --all | --check] [--root DIR] [--map FILE]
#                     [--baseline FILE] [--jobs N] [--timeout SECS] [SCRIPT...]
# Needs jq, sha256sum, timeout and bats on PATH.
set -euo pipefail

# Default timeout per test file when MUTATE_TIMEOUT is unset (2 minutes covers full bats suites).
readonly DEFAULT_TIMEOUT=120
# 12 hex chars of a line's sha256 identify it across line-number shifts without colliding in one file.
readonly LINE_HASH_CHARS=12

# Operator table: "name|from|to|boundary". boundary=1 requires end-of-line, space, ';', or ')' after 'from'.
readonly -a OPERATORS=(
    $'eq-to-ne\t -eq \t -ne \t0'
    $'ne-to-eq\t -ne \t -eq \t0'
    $'lt-to-le\t -lt \t -le \t0'
    $'le-to-lt\t -le \t -lt \t0'
    $'gt-to-ge\t -gt \t -ge \t0'
    $'ge-to-gt\t -ge \t -gt \t0'
    $'streq-to-strne\t == \t != \t0'
    $'strne-to-streq\t != \t == \t0'
    $'and-to-or\t && \t || \t0'
    $'or-to-and\t || \t && \t0'
    $'z-to-n\t -z \t -n \t0'
    $'n-to-z\t -n \t -z \t0'
    $'exit1-to-exit0\texit 1\texit 0\t1'
    $'return1-to-return0\treturn 1\treturn 0\t1'
    $'return0-to-return1\treturn 0\treturn 1\t1'
    $'drop-if-not\tif ! \tif \t0'
    $'drop-test-not\t[[ ! \t[[ \t0'
)

usage() {
    cat >&2 <<'EOF'
usage: mutate-scripts.sh [--changed | --all | --check] [--root DIR] [--map FILE]
                         [--baseline FILE] [--jobs N] [--timeout SECS] [SCRIPT...]
EOF
    exit 2
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode=""
root_arg=""
map_file=""
baseline_file=""
jobs_count=1
timeout_secs="${MUTATE_TIMEOUT:-$DEFAULT_TIMEOUT}"
declare -a filter_scripts=()

while (($# > 0)); do
    case "$1" in
        --changed|--all|--check)
            if [[ -n "$mode" ]]; then
                usage
            fi
            mode="${1#--}"
            shift
            ;;
        --root)
            (($# >= 2)) || usage
            root_arg="$2"
            shift 2
            ;;
        --map)
            (($# >= 2)) || usage
            map_file="$2"
            shift 2
            ;;
        --baseline)
            (($# >= 2)) || usage
            baseline_file="$2"
            shift 2
            ;;
        --jobs)
            (($# >= 2)) || usage
            jobs_count="$2"
            shift 2
            ;;
        --timeout)
            (($# >= 2)) || usage
            timeout_secs="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        -*)
            usage
            ;;
        *)
            filter_scripts+=("$1")
            shift
            ;;
    esac
done

mode="${mode:-changed}"
if [[ ! "$jobs_count" =~ ^[1-9][0-9]*$ ]]; then
    usage
fi
if [[ ! "$timeout_secs" =~ ^[1-9][0-9]*$ ]]; then
    usage
fi

if [[ -n "$root_arg" ]]; then
    if [[ ! -d "$root_arg" ]]; then
        echo "error: root directory not found: $root_arg" >&2
        exit 2
    fi
    root_dir="$(cd "$root_arg" && pwd)"
else
    root_dir="$(cd "$script_dir/../.." && pwd)"
fi
map_file="${map_file:-"$script_dir/../mutation/map.json"}"
baseline_file="${baseline_file:-"$script_dir/../mutation/baseline.json"}"

if [[ ! -f "$map_file" ]]; then
    echo "error: map file not found: $map_file" >&2
    exit 2
fi

map_json="$(cat "$map_file")"
if ! jq -e . >/dev/null 2>&1 <<<"$map_json"; then
    echo "error: invalid JSON in map file: $map_file" >&2
    exit 2
fi

map_version="$(jq -r '.version // "1"' <<<"$map_json")"

if [[ -f "$baseline_file" ]]; then
    baseline_json="$(cat "$baseline_file")"
else
    baseline_json='{"pairs": {}}'
fi

validate_map() {
    local key test_rel
    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        if jq -e --arg k "$key" '(.exclude // {}) | has($k)' >/dev/null <<<"$map_json"; then
            echo "error: $key is both mapped and excluded" >&2
            exit 2
        fi
        if [[ ! -f "$root_dir/$key" ]]; then
            echo "error: map names missing script $key" >&2
            exit 2
        fi
        while IFS= read -r test_rel; do
            [[ -n "$test_rel" ]] || continue
            if [[ ! -f "$root_dir/$test_rel" ]]; then
                echo "error: $key: no test file $test_rel" >&2
                exit 2
            fi
        done < <(jq -r --arg k "$key" '.pairs[$k][]' <<<"$map_json")
    done < <(jq -r '(.pairs // {}) | keys[]' <<<"$map_json")

    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        if [[ ! -f "$root_dir/$key" ]]; then
            echo "error: map names missing script $key" >&2
            exit 2
        fi
    done < <(jq -r '(.exclude // {}) | keys[]' <<<"$map_json")
}

validate_map

discover_scripts() {
    (
        cd "$root_dir"
        find . -mindepth 3 -type f -path './*/scripts/*.sh' ! -path '*/tests/*' \
            | sed 's|^\./||' \
            | LC_ALL=C sort
    )
}

declare -a all_scripts=()
while IFS= read -r s; do
    [[ -n "$s" ]] && all_scripts+=("$s")
done < <(discover_scripts)

declare -A in_filter=()
if ((${#filter_scripts[@]} > 0)); then
    for s in "${filter_scripts[@]}"; do
        in_filter["$s"]=1
    done
fi

sha256_file() {
    local out
    out="$(sha256sum "$1")"
    echo "${out%% *}"
}

sha256_str() {
    local out
    out="$(printf '%s' "$1" | sha256sum)"
    echo "${out%% *}"
}

trim_ws() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

compute_pair_hash() {
    local script_rel="$1"
    shift
    local -a sorted_tests=()
    local t
    while IFS= read -r t; do
        [[ -n "$t" ]] && sorted_tests+=("$t")
    done < <(printf '%s\n' "$@" | LC_ALL=C sort)

    local buf="version ${map_version}"$'\n'
    buf+="${script_rel} $(sha256_file "$root_dir/$script_rel")"
    for t in "${sorted_tests[@]}"; do
        buf+=$'\n'"${t} $(sha256_file "$root_dir/$t")"
    done
    local digest
    digest="$(printf '%s\n' "$buf" | sha256sum)"
    echo "${digest%% *}"
}

is_accepted() {
    local script_rel="$1" op="$2" line_hash="$3" occ="$4"
    jq -e --arg s "$script_rel" --arg op "$op" --arg lh "$line_hash" --argjson occ "$occ" \
        '(.accepted // []) | any(.script == $s and .op == $op and .line_hash == $lh and .occurrence == $occ)' \
        >/dev/null <<<"$map_json"
}

has_unaccepted_survivor() {
    local script_rel="$1" entry_json="$2"
    jq -e --arg s "$script_rel" --argjson acc "$(jq '.accepted // []' <<<"$map_json")" '
        (.survivors // []) | any(
            . as $surv |
            ($acc | any(.script == $s and .op == $surv.op and .line_hash == $surv.line_hash and .occurrence == $surv.occurrence)) | not
        )
    ' >/dev/null <<<"$entry_json"
}

count_unaccepted_survivors() {
    local script_rel="$1" entry_json="$2"
    jq -r --arg s "$script_rel" --argjson acc "$(jq '.accepted // []' <<<"$map_json")" '
        [ (.survivors // [])[] |
          . as $surv |
          select(($acc | any(.script == $s and .op == $surv.op and .line_hash == $surv.line_hash and .occurrence == $surv.occurrence)) | not)
        ] | length
    ' <<<"$entry_json"
}

# Emits mutation points for a script file as tab-separated lines:
# line_no \t col_offset \t op_name \t from_len \t to_str \t line_hash \t occurrence
find_mutations() {
    local file="$1"
    local -a lines=()
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done <"$file"

    local in_heredoc=0 heredoc_word="" heredoc_strip_tabs=0
    local total="${#lines[@]}"
    local idx line_no trimmed search_part
    local -A occ_counts=()

    local hd_re='<<(-?)(['"'"'"]?)([A-Za-z_][A-Za-z0-9_]*)\2'

    for ((idx = 0; idx < total; idx++)); do
        line="${lines[$idx]}"
        line_no=$((idx + 1))

        if ((in_heredoc)); then
            local check_line="$line"
            if ((heredoc_strip_tabs)); then
                check_line="${check_line#"${check_line%%[!$'\t']*}"}"
            fi
            if [[ "$check_line" == "$heredoc_word" ]]; then
                in_heredoc=0
                heredoc_word=""
                heredoc_strip_tabs=0
            fi
            continue
        fi

        trimmed="${line#"${line%%[![:space:]]*}"}"
        if [[ -z "$trimmed" || "${trimmed:0:1}" == "#" ]]; then
            continue
        fi

        search_part="$line"
        if [[ "$search_part" == *" #"* ]]; then
            search_part="${search_part%% \#*}"
        fi

        local without_herestr="${search_part//<<</}"
        if [[ "$without_herestr" =~ $hd_re ]]; then
            in_heredoc=1
            if [[ "${BASH_REMATCH[1]}" == "-" ]]; then
                heredoc_strip_tabs=1
            else
                heredoc_strip_tabs=0
            fi
            heredoc_word="${BASH_REMATCH[3]}"
        fi

        local full_hash line_hash
        full_hash="$(sha256_str "$line")"
        line_hash="${full_hash:0:$LINE_HASH_CHARS}"

        local op_entry op_name op_from op_to op_boundary
        for op_entry in "${OPERATORS[@]}"; do
            IFS=$'\t' read -r op_name op_from op_to op_boundary <<<"$op_entry"
            local from_len="${#op_from}"
            local search_len="${#search_part}"
            local pos=0
            while ((pos + from_len <= search_len)); do
                local sub="${search_part:pos}"
                if [[ "$sub" != *"$op_from"* ]]; then
                    break
                fi
                local prefix="${sub%%"$op_from"*}"
                local match_col=$((pos + ${#prefix}))
                local valid=1
                if ((op_boundary == 1)); then
                    local after_idx=$((match_col + from_len))
                    if ((after_idx < ${#line})); then
                        local next_ch="${line:after_idx:1}"
                        if [[ "$next_ch" != " " && "$next_ch" != ";" && "$next_ch" != ")" ]]; then
                            valid=0
                        fi
                    fi
                fi
                if ((valid == 1)); then
                    local key="${op_name}:${line_hash}"
                    local occ="${occ_counts[$key]:-0}"
                    occ_counts["$key"]=$((occ + 1))
                    printf '%d\t%d\t%s\t%d\t%s\t%s\t%d\n' \
                        "$line_no" "$match_col" "$op_name" "$from_len" "$op_to" "$line_hash" "$occ"
                fi
                pos=$((match_col + 1))
            done
        done
    done
}

write_mutant() {
    local src_file="$1" dst_file="$2" target_line="$3" col="$4" from_len="$5" to_str="$6"
    local -a lines=()
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done <"$src_file"

    local idx=$((target_line - 1))
    local orig="${lines[$idx]}"
    local mutated="${orig:0:col}${to_str}${orig:col+from_len}"
    lines[idx]="$mutated"

    printf '%s\n' "${lines[@]}" >"$dst_file"
}

run_suite_in_copy() {
    local copy_root="$1"
    shift
    local -a sorted_tests=()
    local t
    while IFS= read -r t; do
        [[ -n "$t" ]] && sorted_tests+=("$t")
    done < <(printf '%s\n' "$@" | LC_ALL=C sort)

    local test_rel test_path test_dir test_base rc
    for test_rel in "${sorted_tests[@]}"; do
        test_path="$copy_root/$test_rel"
        test_dir="$(dirname "$test_path")"
        test_base="$(basename "$test_path")"
        rc=0
        if [[ "$test_base" == *.bats ]]; then
            (cd "$test_dir" && timeout "$timeout_secs" bats "$test_base" >/dev/null 2>&1) || rc=$?
        else
            (cd "$test_dir" && timeout "$timeout_secs" bash "$test_base" >/dev/null 2>&1) || rc=$?
        fi
        if ((rc != 0)); then
            return 1
        fi
    done
    return 0
}

run_one_pair() {
    local script_rel="$1" pair_hash="$2" result_file="$3"
    shift 3
    local -a tests=("$@")

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    cp -a "$root_dir/." "$tmp_dir/skills/"
    local copy_root="$tmp_dir/skills"
    local copy_script="$copy_root/$script_rel"
    local orig_backup="$tmp_dir/orig_script"
    cp -a "$copy_script" "$orig_backup"

    local ran_at
    ran_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if ! run_suite_in_copy "$copy_root" "${tests[@]}"; then
        printf 'NOT TESTED %s: tests fail without mutation\n' "$script_rel"
        jq -n \
            --arg script "$script_rel" \
            --arg hash "$pair_hash" \
            --arg ran_at "$ran_at" \
            '{
                script: $script,
                failed: true,
                entry: {
                    hash: $hash,
                    status: "not-tested",
                    mutants: 0,
                    killed: 0,
                    survivors: [],
                    ran_at: $ran_at
                }
            }' >"$result_file"
        rm -rf "$tmp_dir"
        return 0
    fi

    local -a orig_lines=()
    local l
    while IFS= read -r l || [[ -n "$l" ]]; do
        orig_lines+=("$l")
    done <"$orig_backup"

    local mutants=0 killed=0 unaccepted_survivors=0
    local survivors_json="[]"
    local line_no col op_name from_len to_str line_hash occ

    while IFS=$'\t' read -r line_no col op_name from_len to_str line_hash occ; do
        [[ -n "$line_no" ]] || continue
        mutants=$((mutants + 1))
        write_mutant "$orig_backup" "$copy_script" "$line_no" "$col" "$from_len" "$to_str"
        if ! run_suite_in_copy "$copy_root" "${tests[@]}"; then
            killed=$((killed + 1))
        else
            local raw_line="${orig_lines[$((line_no - 1))]}"
            local trimmed_text
            trimmed_text="$(trim_ws "$raw_line")"
            if is_accepted "$script_rel" "$op_name" "$line_hash" "$occ"; then
                printf 'SURVIVED %s:%d %s: %s (accepted)\n' "$script_rel" "$line_no" "$op_name" "$trimmed_text"
            else
                printf 'SURVIVED %s:%d %s: %s\n' "$script_rel" "$line_no" "$op_name" "$trimmed_text"
                unaccepted_survivors=$((unaccepted_survivors + 1))
            fi
            survivors_json="$(jq -c \
                --arg op "$op_name" \
                --argjson line "$line_no" \
                --arg lh "$line_hash" \
                --argjson occ "$occ" \
                --arg text "$trimmed_text" \
                '. + [{op: $op, line: $line, line_hash: $lh, occurrence: $occ, text: $text}]' \
                <<<"$survivors_json")"
        fi
        cp -a "$orig_backup" "$copy_script"
    done < <(find_mutations "$orig_backup")

    printf '%s: killed %d/%d\n' "$script_rel" "$killed" "$mutants"

    local pair_failed="false"
    if ((unaccepted_survivors > 0)); then
        pair_failed="true"
    fi

    jq -n \
        --arg script "$script_rel" \
        --arg hash "$pair_hash" \
        --arg ran_at "$ran_at" \
        --argjson mutants "$mutants" \
        --argjson killed "$killed" \
        --argjson survivors "$survivors_json" \
        --argjson failed "$pair_failed" \
        --argjson unaccepted "$unaccepted_survivors" \
        '{
            script: $script,
            failed: $failed,
            unaccepted: $unaccepted,
            entry: {
                hash: $hash,
                status: "tested",
                mutants: $mutants,
                killed: $killed,
                survivors: $survivors,
                ran_at: $ran_at
            }
        }' >"$result_file"

    rm -rf "$tmp_dir"
}

declare -a covered_scripts=()
declare -A script_tests=()
declare -A active_covered=()
unmapped_count=0

for script_rel in "${all_scripts[@]}"; do
    has_pair="$(jq -r --arg k "$script_rel" '(.pairs // {}) | has($k)' <<<"$map_json")"
    is_excl="$(jq -r --arg k "$script_rel" '(.exclude // {}) | has($k)' <<<"$map_json")"
    resolved_tests=""

    if [[ "$has_pair" == "true" ]]; then
        resolved_tests="$(jq -r --arg k "$script_rel" '.pairs[$k][]' <<<"$map_json")"
    else
        skill_name="${script_rel%%/*}"
        base_name="$(basename "$script_rel" .sh)"
        cand_bats="${skill_name}/scripts/tests/${base_name}.bats"
        cand_sh="${skill_name}/scripts/tests/${base_name}.test.sh"
        if [[ -f "$root_dir/$cand_bats" ]]; then
            resolved_tests="$cand_bats"
        elif [[ -f "$root_dir/$cand_sh" ]]; then
            resolved_tests="$cand_sh"
        fi
    fi

    if [[ -n "$resolved_tests" ]]; then
        active_covered["$script_rel"]=1
        if ((${#filter_scripts[@]} > 0)) && [[ -z "${in_filter[$script_rel]:-}" ]]; then
            continue
        fi
        covered_scripts+=("$script_rel")
        script_tests["$script_rel"]="$resolved_tests"
    elif [[ "$is_excl" == "true" ]]; then
        continue
    else
        if ((${#filter_scripts[@]} > 0)) && [[ -z "${in_filter[$script_rel]:-}" ]]; then
            continue
        fi
        printf 'UNMAPPED %s\n' "$script_rel"
        unmapped_count=$((unmapped_count + 1))
    fi
done

if [[ "$mode" == "check" ]]; then
    stale_count=0
    current_count=0
    for script_rel in "${covered_scripts[@]}"; do
        declare -a t_arr=()
        while IFS= read -r t; do
            [[ -n "$t" ]] && t_arr+=("$t")
        done <<<"${script_tests[$script_rel]}"
        pair_hash="$(compute_pair_hash "$script_rel" "${t_arr[@]}")"

        has_base="$(jq -r --arg k "$script_rel" '(.pairs // {}) | has($k)' <<<"$baseline_json")"
        if [[ "$has_base" != "true" ]]; then
            printf 'STALE %s\n' "$script_rel"
            stale_count=$((stale_count + 1))
            continue
        fi

        entry_json="$(jq -c --arg k "$script_rel" '.pairs[$k]' <<<"$baseline_json")"
        base_hash="$(jq -r '.hash // ""' <<<"$entry_json")"
        base_status="$(jq -r '.status // ""' <<<"$entry_json")"

        if [[ "$base_hash" != "$pair_hash" ]]; then
            printf 'STALE %s\n' "$script_rel"
            stale_count=$((stale_count + 1))
            continue
        fi

        current_count=$((current_count + 1))
        if [[ "$base_status" == "not-tested" ]]; then
            printf 'NOT TESTED %s\n' "$script_rel"
        fi
        open_surv="$(count_unaccepted_survivors "$script_rel" "$entry_json")"
        if ((open_surv > 0)); then
            printf 'OPEN %s: %d survivor(s)\n' "$script_rel" "$open_surv"
        fi
    done

    if ((stale_count > 0 || unmapped_count > 0)); then
        exit 1
    fi
    printf 'ok: %d pair(s) current\n' "$current_count"
    exit 0
fi

results_dir="$(mktemp -d)"
# shellcheck disable=SC2329 # invoked indirectly via trap
cleanup_results() {
    if [[ -n "${results_dir:-}" && -d "$results_dir" ]]; then
        rm -rf "$results_dir"
    fi
}
trap cleanup_results EXIT

declare -a due_scripts=()
declare -A due_hashes=()
skipped_count=0

for script_rel in "${covered_scripts[@]}"; do
    declare -a t_arr=()
    while IFS= read -r t; do
        [[ -n "$t" ]] && t_arr+=("$t")
    done <<<"${script_tests[$script_rel]}"
    pair_hash="$(compute_pair_hash "$script_rel" "${t_arr[@]}")"

    if [[ "$mode" == "all" ]]; then
        due_scripts+=("$script_rel")
        due_hashes["$script_rel"]="$pair_hash"
        continue
    fi

    has_base="$(jq -r --arg k "$script_rel" '(.pairs // {}) | has($k)' <<<"$baseline_json")"
    if [[ "$has_base" != "true" ]]; then
        due_scripts+=("$script_rel")
        due_hashes["$script_rel"]="$pair_hash"
        continue
    fi

    entry_json="$(jq -c --arg k "$script_rel" '.pairs[$k]' <<<"$baseline_json")"
    base_hash="$(jq -r '.hash // ""' <<<"$entry_json")"
    base_status="$(jq -r '.status // ""' <<<"$entry_json")"

    if [[ "$base_hash" != "$pair_hash" || "$base_status" == "not-tested" ]] || has_unaccepted_survivor "$script_rel" "$entry_json"; then
        due_scripts+=("$script_rel")
        due_hashes["$script_rel"]="$pair_hash"
    else
        skipped_count=$((skipped_count + 1))
    fi
done

running_jobs=0
pair_idx=0
for script_rel in "${due_scripts[@]}"; do
    pair_idx=$((pair_idx + 1))
    res_file="$results_dir/result_${pair_idx}.json"
    pair_hash="${due_hashes[$script_rel]}"
    declare -a t_arr=()
    while IFS= read -r t; do
        [[ -n "$t" ]] && t_arr+=("$t")
    done <<<"${script_tests[$script_rel]}"

    if ((jobs_count == 1)); then
        run_one_pair "$script_rel" "$pair_hash" "$res_file" "${t_arr[@]}"
    else
        run_one_pair "$script_rel" "$pair_hash" "$res_file" "${t_arr[@]}" &
        running_jobs=$((running_jobs + 1))
        if ((running_jobs >= jobs_count)); then
            wait -n || true
            running_jobs=$((running_jobs - 1))
        fi
    fi
done

if ((jobs_count > 1)); then
    wait || true
fi

active_keys_json="$(
    if ((${#active_covered[@]} == 0)); then
        echo '[]'
    else
        printf '%s\n' "${!active_covered[@]}" | jq -R . | jq -s .
    fi
)"

new_baseline="$(jq --argjson active "$active_keys_json" '
    .pairs = ((.pairs // {}) | with_entries(select(.key as $k | ($active | index($k) != null))))
' <<<"$baseline_json")"

total_mutants=0
total_killed=0
total_survivors=0
any_run_failed=0

for res_file in "$results_dir"/result_*.json; do
    [[ -f "$res_file" ]] || continue
    res_json="$(cat "$res_file")"
    s_rel="$(jq -r '.script' <<<"$res_json")"
    entry="$(jq -c '.entry' <<<"$res_json")"
    failed="$(jq -r '.failed' <<<"$res_json")"
    m_cnt="$(jq -r '.entry.mutants' <<<"$res_json")"
    k_cnt="$(jq -r '.entry.killed' <<<"$res_json")"
    surv_cnt="$(jq -r '.entry.survivors | length' <<<"$res_json")"

    total_mutants=$((total_mutants + m_cnt))
    total_killed=$((total_killed + k_cnt))
    total_survivors=$((total_survivors + surv_cnt))
    if [[ "$failed" == "true" ]]; then
        any_run_failed=1
    fi

    new_baseline="$(jq --arg k "$s_rel" --argjson v "$entry" '.pairs[$k] = $v' <<<"$new_baseline")"
done

mkdir -p "$(dirname "$baseline_file")"
tmp_base="$(mktemp "${baseline_file}.tmp.XXXXXX")"
jq -S . <<<"$new_baseline" >"$tmp_base"
mv "$tmp_base" "$baseline_file"

printf 'mutants: %d killed / %d total, %d survivor(s), skipped %d unchanged pair(s)\n' \
    "$total_killed" "$total_mutants" "$total_survivors" "$skipped_count"

if ((unmapped_count > 0 || any_run_failed > 0)); then
    exit 1
fi
exit 0
