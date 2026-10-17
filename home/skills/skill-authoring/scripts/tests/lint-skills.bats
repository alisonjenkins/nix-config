#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../lint-skills.sh"
  skills="$BATS_TEST_TMPDIR/skills"
  mkdir -p "$skills"
}

# make_skill NAME [BODY] [EXTRA_FRONTMATTER_LINE]
make_skill() {
  mkdir -p "$skills/$1"
  {
    printf -- '---\nname: %s\ndescription: >-\n  Use when testing.\n' "$1"
    [ -z "${3:-}" ] || printf '%s\n' "$3"
    printf -- '---\n\n# %s\n\n%s\n' "$1" "${2:-body}"
  } >"$skills/$1/SKILL.md"
}

@test "passes a well-formed skill" {
  make_skill good
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all skills pass"* ]]
}

@test "passes the real shared skills" {
  run bash "$script"
  [ "$status" -eq 0 ]
}

@test "fails a directory with no SKILL.md" {
  mkdir "$skills/empty"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL empty: no SKILL.md"* ]]
}

@test "fails a description over the listing cap" {
  make_skill long
  long="$(printf 'x%.0s' $(seq 1 1600))"
  printf -- '---\nname: long\ndescription: %s\n---\n\nbody\n' "$long" >"$skills/long/SKILL.md"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL long: description is 1600 chars"* ]]
}

@test "accepts a description exactly at the cap" {
  make_skill edge
  edge="$(printf 'x%.0s' $(seq 1 1536))"
  printf -- '---\nname: edge\ndescription: %s\n---\n\nbody\n' "$edge" >"$skills/edge/SKILL.md"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "fails a SKILL.md over 500 lines" {
  make_skill big "$(seq 1 501)"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL big: SKILL.md is"* ]]
}

@test "fails a frontmatter field outside the spec" {
  make_skill ext "body" "paths: [src]"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside the agentskills.io spec: paths"* ]]
}

@test "tolerates argument-hint, the documented exception" {
  make_skill hinted "body" 'argument-hint: "[filter]"'
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "fails a relative link to a missing file" {
  make_skill linky "See [more](more.md)."
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL linky: SKILL.md links to missing more.md"* ]]
}

@test "accepts a relative link that resolves, with an anchor" {
  make_skill linky "See [more](more.md#part)."
  printf '# more\n' >"$skills/linky/more.md"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "checks links in sibling files, relative to that file" {
  make_skill linky
  mkdir "$skills/linky/languages"
  printf 'See [up](../SKILL.md) and [gone](nope.md).\n' >"$skills/linky/languages/go.md"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"languages/go.md links to missing nope.md"* ]]
  [[ "$output" != *"../SKILL.md"* ]]
}

@test "ignores external links, anchors and absolute paths" {
  make_skill ext 'See [a](https://example.com/x.md), [b](#top), [c](/abs.md).'
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "ignores links shown as examples in fences and code spans" {
  make_skill demo '`[x](missing.md)`

```
[y](also-missing.md)
```'
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "fails a script that hardcodes /run/current-system" {
  make_skill pathy
  mkdir "$skills/pathy/scripts"
  printf '#!/usr/bin/env bash\n/run/current-system/sw/bin/jq .\n' >"$skills/pathy/scripts/go.sh"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"scripts/go.sh hardcodes a machine path"* ]]
}

@test "fails a script that hardcodes a home directory" {
  make_skill pathy
  mkdir "$skills/pathy/scripts"
  printf '#!/usr/bin/env bash\ncd /home/someone/work\n' >"$skills/pathy/scripts/go.sh"
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
}

@test "does not mistake a relative path containing home/ for a home directory" {
  make_skill pathy
  mkdir "$skills/pathy/scripts"
  printf '#!/usr/bin/env bash\nSUFFIX=git/nix-config/home/skills/x.sh\n' >"$skills/pathy/scripts/go.sh"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "does not scan test fixtures for machine paths" {
  make_skill pathy
  mkdir -p "$skills/pathy/scripts/tests"
  printf '#!/usr/bin/env bash\n/home/someone/x\n' >"$skills/pathy/scripts/tests/fake.sh"
  run bash "$script" "$skills"
  [ "$status" -eq 0 ]
}

@test "reports every problem, not just the first" {
  make_skill a "See [x](gone.md)."
  make_skill b "See [y](gone.md)."
  run bash "$script" "$skills"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL a:"* ]]
  [[ "$output" == *"FAIL b:"* ]]
  [[ "$output" == *"2 skill convention problem(s)"* ]]
}
