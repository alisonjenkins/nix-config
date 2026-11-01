#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../check-currency.sh"
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

@test "clean registry exits 0" {
  printf 'Here is expected text.\n' > "$BATS_TEST_TMPDIR/page.txt"
  make_registry "[$(make_source)]"
  run bash "$script" --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 0 ]
  [[ "$output" != *"INVALID"* ]]
  [[ "$output" != *"OVERDUE"* ]]
  [[ "$output" != *"STALE"* ]]
  [[ "$output" != *"FETCHFAIL"* ]]
}

@test "expect string at the top of a large page is found, not reported STALE" {
  { printf 'expected text\n'; head -c 4000000 /dev/zero | tr '\0' 'x'; } > "$BATS_TEST_TMPDIR/page.txt"
  make_registry "[$(make_source)]"
  run bash "$script" --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 0 ]
  [[ "$output" != *"STALE"* ]]
}

@test "missing expect string => STALE line + exit 1" {
  printf 'Other text with nothing expected.\n' > "$BATS_TEST_TMPDIR/page.txt"
  make_registry "[$(make_source "sample-doc")]"
  run bash "$script" --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE sample-doc: missing \"expected text\" (feeds: conventions.md, testing.md)"* ]]
}

@test "past review_by => OVERDUE + exit 1" {
  printf 'Here is expected text.\n' > "$BATS_TEST_TMPDIR/page.txt"
  make_registry "[$(make_source "overdue-doc" "file://$BATS_TEST_TMPDIR/page.txt" '["expected text"]' "2026-09-01" "2026-09-25")]"
  run bash "$script" --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 1 ]
  [[ "$output" == *"OVERDUE overdue-doc: review_by 2026-09-25"* ]]
}

@test "review_by too far out for class => INVALID + exit 2" {
  make_registry "[$(make_source "too-far" "file://$BATS_TEST_TMPDIR/page.txt" '[]' "2026-10-01" "2026-11-15" "official")]"
  run bash "$script" --registry "$BATS_TEST_TMPDIR/registry.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"INVALID too-far:"* ]]
}

@test "duplicate id => INVALID" {
  make_registry "[$(make_source "dup-id"), $(make_source "dup-id")]"
  run bash "$script" --registry "$BATS_TEST_TMPDIR/registry.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"INVALID dup-id: duplicate id"* ]]
}

@test "feeds entry that is not a file next to the registry => INVALID + exit 2" {
  local source
  source="$(make_source "missing-feed" | sed 's/"conventions.md"/"nope.md"/')"
  make_registry "[$source]"
  run bash "$script" --registry "$BATS_TEST_TMPDIR/registry.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"INVALID missing-feed: feeds entry \"nope.md\" is not a file next to the registry"* ]]
}

@test "--offline skips fetch (url points at a nonexistent file, still exit 0 when not overdue)" {
  make_registry "[$(make_source "offline-test" "file://$BATS_TEST_TMPDIR/nonexistent.html")]"
  run bash "$script" --offline --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 0 ]
  [[ "$output" != *"FETCHFAIL"* ]]
}

@test "unreachable url => FETCHFAIL" {
  make_registry "[$(make_source "unreachable" "file:///nonexistent")]"
  export CURRENCY_RETRY_SLEEP=0
  run bash "$script" --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FETCHFAIL unreachable: file:///nonexistent"* ]]
}

@test "prints summary line to stderr" {
  printf 'Here is expected text.\n' > "$BATS_TEST_TMPDIR/page.txt"
  make_registry "[$(make_source)]"
  run bash "$script" --registry "$BATS_TEST_TMPDIR/registry.json" --today "2026-10-28"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checked=1 overdue=0 stale=0 fetchfail=0"* ]]
}

@test "real guidance-sources.json passes offline validation" {
  run bash "$script" --offline --today "2026-10-28"
  [ "$status" -eq 0 ]
}
