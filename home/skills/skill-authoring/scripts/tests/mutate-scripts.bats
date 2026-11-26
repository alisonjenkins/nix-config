#!/usr/bin/env bats

setup() {
    script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    script="$script_dir/../mutate-scripts.sh"
    export MUTATE_TIMEOUT=20

    root="$BATS_TEST_TMPDIR/root"
    map="$BATS_TEST_TMPDIR/map.json"
    base="$BATS_TEST_TMPDIR/baseline.json"

    mkdir -p "$root/demo/scripts/tests"

    cat >"$root/demo/scripts/sign.sh" <<'EOF'
#!/bin/sh
if [ "$1" -lt 0 ]; then
    echo "neg"
else
    echo "pos"
fi
EOF
    chmod +x "$root/demo/scripts/sign.sh"

    cat >"$root/demo/scripts/tests/sign.bats" <<'EOF'
#!/usr/bin/env bats

@test "negative input prints neg" {
    run ../sign.sh -1
    [ "$status" -eq 0 ]
    [ "$output" = "neg" ]
}

@test "zero input prints pos" {
    run ../sign.sh 0
    [ "$status" -eq 0 ]
    [ "$output" = "pos" ]
}
EOF

    cat >"$map" <<'EOF'
{
  "version": "1",
  "pairs": {},
  "exclude": {},
  "accepted": []
}
EOF
}

@test "a mutant the tests catch is killed" {
    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"demo/scripts/sign.sh: killed 1/1"* ]]
    [[ "$output" != *"SURVIVED"* ]]
}

@test "a mutant the tests miss survives" {
    cat >"$root/demo/scripts/tests/sign.bats" <<'EOF'
#!/usr/bin/env bats

@test "positive input prints pos" {
    run ../sign.sh 5
    [ "$status" -eq 0 ]
    [ "$output" = "pos" ]
}
EOF
    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 1 ]
    [[ "$output" == *"SURVIVED demo/scripts/sign.sh:2 lt-to-le:"* ]]
    [ "$(jq -r '.pairs["demo/scripts/sign.sh"].survivors | length' "$base")" -eq 1 ]
}

@test "an accepted survivor does not fail the run" {
    cat >"$root/demo/scripts/tests/sign.bats" <<'EOF'
#!/usr/bin/env bats

@test "positive input prints pos" {
    run ../sign.sh 5
    [ "$status" -eq 0 ]
    [ "$output" = "pos" ]
}
EOF
    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 1 ]

    op="$(jq -r '.pairs["demo/scripts/sign.sh"].survivors[0].op' "$base")"
    lh="$(jq -r '.pairs["demo/scripts/sign.sh"].survivors[0].line_hash' "$base")"
    occ="$(jq -r '.pairs["demo/scripts/sign.sh"].survivors[0].occurrence' "$base")"

    jq --arg op "$op" --arg lh "$lh" --argjson occ "$occ" \
        '.accepted = [{"script": "demo/scripts/sign.sh", "op": $op, "line_hash": $lh, "occurrence": $occ, "reason": "boundary tested elsewhere"}]' \
        "$map" >"$map.tmp" && mv "$map.tmp" "$map"

    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SURVIVED demo/scripts/sign.sh:2 lt-to-le:"*" (accepted)"* ]]
}

@test "--changed skips an unchanged pair" {
    counter="$BATS_TEST_TMPDIR/runs.log"
    : >"$counter"
    cat >"$root/demo/scripts/tests/sign.bats" <<EOF
#!/usr/bin/env bats

@test "checks both branches and logs run" {
    echo run >>"$counter"
    run ../sign.sh -1
    [ "\$output" = "neg" ]
    run ../sign.sh 0
    [ "\$output" = "pos" ]
}
EOF
    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    before="$(wc -l <"$counter")"
    [ "$before" -ge 1 ]

    run bash "$script" --changed --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped 1 unchanged pair(s)"* ]]
    after="$(wc -l <"$counter")"
    [ "$after" -eq "$before" ]
}

@test "--changed reruns a pair whose test file changed" {
    counter="$BATS_TEST_TMPDIR/runs.log"
    : >"$counter"
    cat >"$root/demo/scripts/tests/sign.bats" <<EOF
#!/usr/bin/env bats

@test "checks both branches" {
    echo run >>"$counter"
    run ../sign.sh -1
    [ "\$output" = "neg" ]
    run ../sign.sh 0
    [ "\$output" = "pos" ]
}
EOF
    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    before="$(wc -l <"$counter")"

    echo "# comment edit" >>"$root/demo/scripts/tests/sign.bats"

    run bash "$script" --changed --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    after="$(wc -l <"$counter")"
    [ "$after" -gt "$before" ]
}

@test "--changed reruns a pair whose script changed" {
    counter="$BATS_TEST_TMPDIR/runs.log"
    : >"$counter"
    cat >"$root/demo/scripts/tests/sign.bats" <<EOF
#!/usr/bin/env bats

@test "checks both branches" {
    echo run >>"$counter"
    run ../sign.sh -1
    [ "\$output" = "neg" ]
    run ../sign.sh 0
    [ "\$output" = "pos" ]
}
EOF
    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    before="$(wc -l <"$counter")"

    echo "# script comment edit" >>"$root/demo/scripts/sign.sh"

    run bash "$script" --changed --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    after="$(wc -l <"$counter")"
    [ "$after" -gt "$before" ]
}

@test "--changed reruns an unchanged pair that still has survivors" {
    counter="$BATS_TEST_TMPDIR/runs.log"
    : >"$counter"
    cat >"$root/demo/scripts/tests/sign.bats" <<EOF
#!/usr/bin/env bats

@test "only checks positive case" {
    echo run >>"$counter"
    run ../sign.sh 5
    [ "\$output" = "pos" ]
}
EOF
    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 1 ]
    before="$(wc -l <"$counter")"

    run bash "$script" --changed --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 1 ]
    [[ "$output" == *"SURVIVED demo/scripts/sign.sh:"* ]]
    after="$(wc -l <"$counter")"
    [ "$after" -gt "$before" ]
}

@test "--check fails on a stale pair and passes after --all" {
    run bash "$script" --check --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 1 ]
    [[ "$output" == *"STALE demo/scripts/sign.sh"* ]]

    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]

    run bash "$script" --check --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok: 1 pair(s) current"* ]]
}

@test "an unmapped script fails every mode with UNMAPPED and adding it to exclude makes --check pass" {
    cat >"$root/demo/scripts/other.sh" <<'EOF'
#!/bin/sh
echo "other"
EOF
    chmod +x "$root/demo/scripts/other.sh"

    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 1 ]
    [[ "$output" == *"UNMAPPED demo/scripts/other.sh"* ]]

    run bash "$script" --changed --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 1 ]
    [[ "$output" == *"UNMAPPED demo/scripts/other.sh"* ]]

    run bash "$script" --check --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 1 ]
    [[ "$output" == *"UNMAPPED demo/scripts/other.sh"* ]]

    jq '.exclude["demo/scripts/other.sh"] = "no tests yet"' "$map" >"$map.tmp" && mv "$map.tmp" "$map"

    run bash "$script" --check --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok: 1 pair(s) current"* ]]
}

@test "a suite that fails without mutation marks the pair not-tested" {
    cat >"$root/demo/scripts/tests/sign.bats" <<'EOF'
#!/usr/bin/env bats

@test "broken test fails immediately" {
    [ 1 -eq 2 ]
}
EOF
    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 1 ]
    [[ "$output" == *"NOT TESTED demo/scripts/sign.sh: tests fail without mutation"* ]]
    [ "$(jq -r '.pairs["demo/scripts/sign.sh"].status' "$base")" = "not-tested" ]
}

@test "the real root is never modified" {
    before_sha="$(sha256sum "$root/demo/scripts/sign.sh")"
    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    after_sha="$(sha256sum "$root/demo/scripts/sign.sh")"
    [ "$before_sha" = "$after_sha" ]
}

@test "comments and heredoc bodies are not mutated" {
    cat >"$root/demo/scripts/sign.sh" <<'EOF'
#!/bin/sh
# if [ "$1" -lt 0 ]; then
cat <<'END'
if [ "$1" -lt 0 ]; then
    echo "inside heredoc"
fi
END
echo "ok" # if [ "$1" -lt 0 ]; then
EOF
    chmod +x "$root/demo/scripts/sign.sh"

    cat >"$root/demo/scripts/tests/sign.bats" <<'EOF'
#!/usr/bin/env bats

@test "runs sign.sh" {
    run ../sign.sh
    [ "$status" -eq 0 ]
}
EOF
    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"demo/scripts/sign.sh: killed 0/0"* ]]
    [ "$(jq -r '.pairs["demo/scripts/sign.sh"].mutants' "$base")" -eq 0 ]
}

@test "exit 10 is not mutated by exit1-to-exit0" {
    cat >"$root/demo/scripts/sign.sh" <<'EOF'
#!/bin/sh
exit 10
EOF
    chmod +x "$root/demo/scripts/sign.sh"

    cat >"$root/demo/scripts/tests/sign.bats" <<'EOF'
#!/usr/bin/env bats

@test "exits 10" {
    run ../sign.sh
    [ "$status" -eq 10 ]
}
EOF
    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 0 ]
    [[ "$output" == *"demo/scripts/sign.sh: killed 0/0"* ]]
    [ "$(jq -r '.pairs["demo/scripts/sign.sh"].mutants' "$base")" -eq 0 ]
}

@test "a map test path that does not exist exits 2 with the error text" {
    jq '.pairs["demo/scripts/sign.sh"] = ["demo/scripts/tests/missing.bats"]' "$map" >"$map.tmp" && mv "$map.tmp" "$map"
    run bash "$script" --all --root "$root" --map "$map" --baseline "$base"
    [ "$status" -eq 2 ]
    [[ "$output" == *"error: demo/scripts/sign.sh: no test file demo/scripts/tests/missing.bats"* ]]
}

@test "--jobs 2 with two mapped scripts gives the same baseline pairs as --jobs 1" {
    cat >"$root/demo/scripts/second.sh" <<'EOF'
#!/bin/sh
if [ "$1" -eq 0 ]; then
    echo "zero"
else
    echo "nonzero"
fi
EOF
    chmod +x "$root/demo/scripts/second.sh"

    cat >"$root/demo/scripts/tests/second.bats" <<'EOF'
#!/usr/bin/env bats

@test "zero and nonzero" {
    run ../second.sh 0
    [ "$output" = "zero" ]
    run ../second.sh 1
    [ "$output" = "nonzero" ]
}
EOF

    base1="$BATS_TEST_TMPDIR/base1.json"
    base2="$BATS_TEST_TMPDIR/base2.json"

    run bash "$script" --all --jobs 1 --root "$root" --map "$map" --baseline "$base1"
    [ "$status" -eq 0 ]

    run bash "$script" --all --jobs 2 --root "$root" --map "$map" --baseline "$base2"
    [ "$status" -eq 0 ]

    norm1="$(jq -S 'del(.pairs[].ran_at)' "$base1")"
    norm2="$(jq -S 'del(.pairs[].ran_at)' "$base2")"
    [ "$norm1" = "$norm2" ]
}
