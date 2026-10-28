#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../raise-currency-issue.sh"

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat << 'EOF' > "$BATS_TEST_TMPDIR/bin/gh"
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$BATS_TEST_TMPDIR/gh.log"
if [[ "${1:-}" == "issue" && "${2:-}" == "list" ]]; then
  if [[ -f "$BATS_TEST_TMPDIR/issues.json" ]]; then
    cat "$BATS_TEST_TMPDIR/issues.json"
  else
    echo "[]"
  fi
fi
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  echo "[]" > "$BATS_TEST_TMPDIR/issues.json"
  : > "$BATS_TEST_TMPDIR/gh.log"
}

make_registry() {
  local sources_json="$1"
  touch "$BATS_TEST_TMPDIR/conventions.md" "$BATS_TEST_TMPDIR/testing.md"
  cat << EOF > "$BATS_TEST_TMPDIR/registry.json"
{
  "max_review_days": {
    "official": 30,
    "community": 60
  },
  "sources": $sources_json
}
EOF
}

make_source() {
  local id="${1:-test-source}"
  local url="${2:-file://$BATS_TEST_TMPDIR/page.txt}"
  local expect="${3:-[\"expected text\"]}"
  local reviewed="${4:-2026-10-28}"
  local review_by="${5:-2026-11-27}"
  local class="${6:-official}"
  cat << EOF
{
  "id": "$id",
  "class": "$class",
  "url": "$url",
  "tracks": "sample tracking",
  "feeds": ["conventions.md", "testing.md"],
  "expect": $expect,
  "reviewed": "$reviewed",
  "review_by": "$review_by",
  "review_note": "A note"
}
EOF
}

@test "checker failure with no findings does not close an open issue" {
  echo '[{"number":7,"title":"Skill guidance sources need review"}]' > "$BATS_TEST_TMPDIR/issues.json"
  run bash "$script" --repo "testowner/testrepo" --registry "$BATS_TEST_TMPDIR/missing.json" --today "2026-10-28"
  [ "$status" -eq 1 ]
  local log
  log="$(cat "$BATS_TEST_TMPDIR/gh.log")"
  [[ "$log" != *"issue close"* ]]
  [[ "$log" != *"issue comment"* ]]
}

@test "runs with no pass-through flags" {
  run bash "$script" --repo "testowner/testrepo" --dry-run --offline --today "2026-10-28"
  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
}

@test "findings and no existing issue creates a new issue" {
  printf 'Other text with nothing expected.\n' > "$BATS_TEST_TMPDIR/page.txt"
  make_registry "[$(make_source "sample-doc")]"
  run bash "$script" --repo "testowner/testrepo" --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 0 ]
  [[ "$output" == *"created"* ]]
  local log
  log="$(cat "$BATS_TEST_TMPDIR/gh.log")"
  [[ "$log" == *"issue create"* ]]
  [[ "$log" != *"issue edit"* ]]
}

@test "findings and existing issue edits the existing issue" {
  printf 'Other text with nothing expected.\n' > "$BATS_TEST_TMPDIR/page.txt"
  make_registry "[$(make_source "sample-doc")]"
  echo '[{"number": 7, "title": "Skill guidance sources need review"}]' > "$BATS_TEST_TMPDIR/issues.json"
  run bash "$script" --repo "testowner/testrepo" --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 0 ]
  [[ "$output" == *"edited #7"* ]]
  local log
  log="$(cat "$BATS_TEST_TMPDIR/gh.log")"
  [[ "$log" == *"issue edit 7"* ]]
}

@test "clean and existing issue comments and closes the issue" {
  printf 'Here is expected text.\n' > "$BATS_TEST_TMPDIR/page.txt"
  make_registry "[$(make_source)]"
  echo '[{"number": 7, "title": "Skill guidance sources need review"}]' > "$BATS_TEST_TMPDIR/issues.json"
  run bash "$script" --repo "testowner/testrepo" --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 0 ]
  [[ "$output" == *"closed #7"* ]]
  local log
  log="$(cat "$BATS_TEST_TMPDIR/gh.log")"
  [[ "$log" == *"issue comment 7"* ]]
  [[ "$log" == *"issue close 7"* ]]
}

@test "clean and no issue leaves log without mutations and outputs nothing to do" {
  printf 'Here is expected text.\n' > "$BATS_TEST_TMPDIR/page.txt"
  make_registry "[$(make_source)]"
  run bash "$script" --repo "testowner/testrepo" --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
  local log
  log="$(cat "$BATS_TEST_TMPDIR/gh.log")"
  [[ "$log" != *"issue create"* ]]
  [[ "$log" != *"issue edit"* ]]
  [[ "$log" != *"issue comment"* ]]
  [[ "$log" != *"issue close"* ]]
}

@test "dry-run with findings outputs would create and performs no mutations" {
  printf 'Other text with nothing expected.\n' > "$BATS_TEST_TMPDIR/page.txt"
  make_registry "[$(make_source "sample-doc")]"
  run bash "$script" --dry-run --repo "testowner/testrepo" --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would create"* ]]
  [[ "$output" == *"The monthly check found sources to review:"* ]]
  local log
  log="$(cat "$BATS_TEST_TMPDIR/gh.log")"
  [[ "$log" != *"issue create"* ]]
  [[ "$log" != *"issue edit"* ]]
  [[ "$log" != *"issue comment"* ]]
  [[ "$log" != *"issue close"* ]]
}

@test "similarly titled issue is not matched and creates a new issue" {
  printf 'Other text with nothing expected.\n' > "$BATS_TEST_TMPDIR/page.txt"
  make_registry "[$(make_source "sample-doc")]"
  echo '[{"number": 8, "title": "Skill guidance sources need review later"}]' > "$BATS_TEST_TMPDIR/issues.json"
  run bash "$script" --repo "testowner/testrepo" --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 0 ]
  [[ "$output" == *"created"* ]]
  local log
  log="$(cat "$BATS_TEST_TMPDIR/gh.log")"
  [[ "$log" == *"issue create"* ]]
  [[ "$log" != *"issue edit"* ]]
}

@test "dry-run without repo skips issue lookup and outputs would create" {
  printf 'Other text with nothing expected.\n' > "$BATS_TEST_TMPDIR/page.txt"
  make_registry "[$(make_source "sample-doc")]"
  run bash "$script" --dry-run --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would create"* ]]
  local log
  log="$(cat "$BATS_TEST_TMPDIR/gh.log")"
  [ -z "$log" ]
}

@test "missing repo without dry-run exits 2" {
  run bash "$script" --today "2026-10-28"
  [ "$status" -eq 2 ]
}
