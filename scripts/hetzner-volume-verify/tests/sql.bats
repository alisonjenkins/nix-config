#!/usr/bin/env bats
# table-checksums.sql against a real, throwaway Postgres (no cluster, no mock).
# Skipped when initdb is not on PATH; the dev shell provides it.

setup_file() {
  command -v initdb >/dev/null || skip "initdb not on PATH"
  export PGDIR="${BATS_FILE_TMPDIR}/pg"
  initdb -D "$PGDIR/data" -A trust >/dev/null
  pg_ctl -D "$PGDIR/data" -o "-k $PGDIR -c listen_addresses=''" -l "$PGDIR/log" -w start >/dev/null
}

teardown_file() {
  [ -d "${PGDIR:-}" ] && pg_ctl -D "$PGDIR/data" -m immediate stop >/dev/null || true
}

q() { psql -h "$PGDIR" -d postgres -qAt "$@"; }
sums() { q -f "${BATS_TEST_DIRNAME}/../table-checksums.sql"; }

setup() {
  command -v initdb >/dev/null || skip "initdb not on PATH"
  q -c 'drop schema if exists s cascade; drop table if exists users, empty_t;
        create table users(id int, n text); insert into users values (1, $$a$$), (2, $$b$$);
        create table empty_t(x int);
        create schema s; create table s."Odd Name"(v int); insert into s."Odd Name" values (7);'
}

@test "every base table is listed, including an empty one and a quoted name" {
  run sums
  [ "$status" -eq 0 ]
  [[ "$output" == *"public.users|2|"* ]]
  [[ "$output" == *"public.empty_t|0|"* ]]
  [[ "$output" == *"s.Odd Name|1|"* ]]
}

@test "no line is blank or has a missing field" {
  run sums
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [ "$(awk -F'|' '{print NF}' <<<"$line")" -eq 3 ]
    [ -n "$(cut -d'|' -f3 <<<"$line")" ]
  done <<<"$output"
}

@test "changing one row changes that table's checksum and no other" {
  before=$(sums)
  q -c "update users set n = \$\$z\$\$ where id = 2"
  after=$(sums)
  [ "$(grep '^public.users|' <<<"$before")" != "$(grep '^public.users|' <<<"$after")" ]
  [ "$(grep '^s.Odd' <<<"$before")" = "$(grep '^s.Odd' <<<"$after")" ]
}

@test "the checksum does not depend on insertion order" {
  before=$(sums | grep '^public.users|')
  q -c 'delete from users; insert into users values (2, $$b$$), (1, $$a$$);'
  [ "$(sums | grep '^public.users|')" = "$before" ]
}
