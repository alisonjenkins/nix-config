#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../run-behaviour-evals.sh"
  skills="$BATS_TEST_TMPDIR/skills"
  evals="$BATS_TEST_TMPDIR/evals"
  mkdir -p "$skills/demo" "$evals"
  printf -- '---\nname: demo\ndescription: Use for demos.\n---\n\nbody\n' >"$skills/demo/SKILL.md"
}

# make_case CASE [PROMPT_FRONTMATTER] [GRADER_TYPE]
make_case() {
  local dir="$evals/demo/$1" front="${2:-max_turns: 4}" type="${3:-regex}"
  mkdir -p "$dir/graders"
  printf -- '---\n%s\n---\nDo the thing.\n' "$front" >"$dir/prompt.md"
  printf -- '---\ntype: %s\npattern: "x"\n---\n' "$type" >"$dir/graders/g.md"
}

check() {
  run bash "$script" --check --skills "$skills" --evals "$evals" "$@"
}

@test "passes a well-formed case" {
  make_case ok
  check
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: 1 skill(s) checked"* ]]
}

@test "fails a case with no prompt.md" {
  make_case ok
  rm "$evals/demo/ok/prompt.md"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL demo/ok: no prompt.md"* ]]
}

@test "fails a prompt.md key the eval runner would reject" {
  make_case bad "max_turn: 4"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown prompt.md key 'max_turn'"* ]]
}

@test "fails frontmatter that does not parse" {
  make_case bad 'description: "a" b'
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL demo/bad: prompt.md frontmatter does not parse"* ]]
}

@test "fails a prompt.md with no prompt body" {
  make_case empty
  printf -- '---\nmax_turns: 4\n---\n\n' >"$evals/demo/empty/prompt.md"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no prompt body"* ]]
}

@test "fails a case with no graders" {
  make_case bare
  rm "$evals/demo/bare/graders/g.md"
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL demo/bare: no graders/*.md"* ]]
}

@test "fails an unknown grader type" {
  make_case odd "max_turns: 4" contains
  check
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown type 'contains'"* ]]
}

@test "fails evals for a skill that does not exist" {
  mkdir -p "$evals/ghost/c"
  check ghost
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL ghost: no skill at"* ]]
}

@test "a live run packs only the selected skill into the plugin" {
  make_case ok
  mkdir -p "$skills/other" "$BATS_TEST_TMPDIR/bin"
  printf -- '---\nname: other\ndescription: x\n---\n' >"$skills/other/SKILL.md"
  cat >"$BATS_TEST_TMPDIR/bin/claude" <<'STUB'
#!/bin/sh
plugin="$3"
ls "$plugin/skills" >"$BATS_TEST_TMPDIR/skills.txt"
ls "$plugin/evals" >"$BATS_TEST_TMPDIR/cases.txt"
jq -r .name "$plugin/.claude-plugin/plugin.json" >"$BATS_TEST_TMPDIR/name.txt"
printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/args.txt"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" SKILL_EVALS_OUT="$BATS_TEST_TMPDIR/out" \
    run bash "$script" --skills "$skills" --evals "$evals" demo -- --runs 1
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/skills.txt")" = "demo" ]
  [ "$(cat "$BATS_TEST_TMPDIR/cases.txt")" = "ok" ]
  [ "$(cat "$BATS_TEST_TMPDIR/name.txt")" = "skill-eval-demo" ]
  grep -qx -- "--no-publish" "$BATS_TEST_TMPDIR/args.txt"
  grep -qx -- "--runs" "$BATS_TEST_TMPDIR/args.txt"
}

@test "a live run passes the eval's failing exit code through" {
  make_case ok
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" SKILL_EVALS_OUT="$BATS_TEST_TMPDIR/out" \
    run bash "$script" --skills "$skills" --evals "$evals"
  [ "$status" -eq 1 ]
}

@test "a live run defaults a cost ceiling from SKILL_EVALS_MAX_COST_USD" {
  make_case ok
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"$BATS_TEST_TMPDIR/args.txt"\n' >"$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" SKILL_EVALS_OUT="$BATS_TEST_TMPDIR/out" SKILL_EVALS_MAX_COST_USD=0.5 \
    run bash "$script" --skills "$skills" --evals "$evals"
  [ "$status" -eq 0 ]
  grep -qx -- "--max-cost-usd" "$BATS_TEST_TMPDIR/args.txt"
  grep -qx -- "0.5" "$BATS_TEST_TMPDIR/args.txt"
}

@test "a live run keeps a caller's own cost ceiling" {
  make_case ok
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"$BATS_TEST_TMPDIR/args.txt"\n' >"$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" SKILL_EVALS_OUT="$BATS_TEST_TMPDIR/out" \
    run bash "$script" --skills "$skills" --evals "$evals" -- --max-cost-usd 3
  [ "$status" -eq 0 ]
  [ "$(grep -cx -- "--max-cost-usd" "$BATS_TEST_TMPDIR/args.txt")" -eq 1 ]
  grep -qx -- "3" "$BATS_TEST_TMPDIR/args.txt"
}
