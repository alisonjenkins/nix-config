#!/usr/bin/env bats
# check-world.sh: prove every chunk in a Minecraft world's region files is readable (FR-018).
# Fixture worlds are built per test by tests/make-region.py.

setup() {
  script="${BATS_TEST_DIRNAME}/../check-world.sh"
  mkr="${BATS_TEST_DIRNAME}/make-region.py"
  world="${BATS_TEST_TMPDIR}/world"
  mkdir -p "$world"
}

mk() { python3 "$mkr" "$@"; }

@test "a valid world passes and counts every chunk" {
  mk "$world/region/r.0.0.mca" 0,0:zlib 1,0:zlib 31,31:zlib
  mk "$world/region/r.-1.0.mca" 5,5:zlib
  run "$script" "$world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"chunks_read=4 unreadable=0 files=2"* ]]
}

@test "the summary line starts with an ISO8601 UTC timestamp" {
  mk "$world/region/r.0.0.mca" 0,0:zlib
  run "$script" "$world"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\ chunks_read=1 ]]
}

@test "gzip, zlib, lz4 and uncompressed chunks all pass" {
  mk "$world/region/r.0.0.mca" 0,0:gzip 1,0:zlib 2,0:lz4 3,0:none
  run "$script" "$world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"chunks_read=4 unreadable=0 files=1"* ]]
}

@test "truncated compressed data fails naming the file and chunk" {
  mk "$world/region/r.1.-2.mca" 0,0:zlib 3,5:truncated
  run "$script" "$world"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unreadable file=$world/region/r.1.-2.mca chunk=3,5 "* ]]
  [[ "$output" == *"chunks_read=1 unreadable=1 files=1"* ]]
}

@test "the report includes the absolute chunk coordinates" {
  mk "$world/region/r.1.-2.mca" 3,5:truncated
  run "$script" "$world"
  [ "$status" -eq 1 ]
  [[ "$output" == *"abs=35,-59"* ]]
}

@test "a location entry pointing outside the file fails" {
  mk "$world/region/r.0.0.mca" 0,0:zlib 7,9:outside
  run "$script" "$world"
  [ "$status" -eq 1 ]
  [[ "$output" == *"chunk=7,9 reason="* ]]
  [[ "$output" == *"chunks_read=1 unreadable=1"* ]]
}

@test "an unknown compression type fails" {
  mk "$world/region/r.0.0.mca" 2,2:badcomp
  run "$script" "$world"
  [ "$status" -eq 1 ]
  [[ "$output" == *"chunk=2,2 reason="*"compression"* ]]
}

@test "decompressed data that is not NBT fails" {
  mk "$world/region/r.0.0.mca" 4,1:badnbt
  run "$script" "$world"
  [ "$status" -eq 1 ]
  [[ "$output" == *"chunk=4,1 reason="*"nbt"* ]]
}

@test "one bad chunk does not hide the others" {
  mk "$world/region/r.0.0.mca" 0,0:badnbt 1,0:truncated 2,0:zlib
  run "$script" "$world"
  [ "$status" -eq 1 ]
  [[ "$output" == *"chunk=0,0 "* ]]
  [[ "$output" == *"chunk=1,0 "* ]]
  [[ "$output" == *"chunks_read=1 unreadable=2"* ]]
}

@test "a missing region directory fails with a clear message" {
  run "$script" "$world"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no region directory"* ]]
}

@test "a region directory with no .mca file fails" {
  mkdir -p "$world/region"
  touch "$world/region/not-a-region.txt"
  run "$script" "$world"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no .mca"* ]]
}

@test "a world with only an entities directory fails" {
  mk "$world/entities/r.0.0.mca" 0,0:zlib
  mk "$world/poi/r.0.0.mca" 0,0:zlib
  run "$script" "$world"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no region directory"* ]]
}

@test "entities and poi are ignored when region is also present" {
  mk "$world/region/r.0.0.mca" 0,0:zlib
  mk "$world/entities/r.0.0.mca" 0,0:badnbt
  run "$script" "$world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"chunks_read=1 unreadable=0 files=1"* ]]
}

@test "nested dimension region directories are all walked" {
  mk "$world/region/r.0.0.mca" 0,0:zlib
  mk "$world/DIM-1/region/r.0.0.mca" 0,0:zlib
  mk "$world/DIM1/region/r.0.0.mca" 0,0:zlib
  mk "$world/dimensions/minecraft/the_nether/region/r.0.0.mca" 0,0:zlib 1,1:zlib
  mk "$world/dimensions/mymod/deep/region/r.0.0.mca" 9,9:badnbt
  run "$script" "$world"
  [ "$status" -eq 1 ]
  [[ "$output" == *"chunks_read=5 unreadable=1 files=5"* ]]
  [[ "$output" == *"dimensions/mymod/deep/region/r.0.0.mca chunk=9,9"* ]]
}

@test "no argument exits 2 with usage" {
  run "$script"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "a non-directory argument exits 2 naming it" {
  run "$script" "$world/nope"
  [ "$status" -eq 2 ]
  [[ "$output" == *"$world/nope"* ]]
}

@test "the world is not modified" {
  mk "$world/region/r.0.0.mca" 0,0:zlib 3,5:truncated
  mk "$world/DIM-1/region/r.0.0.mca" 1,1:lz4
  before=$(cd "$world" && find . -type f -exec sha256sum {} + | sort; find . -printf '%p %T@\n' | sort)
  run "$script" "$world"
  [ "$status" -eq 1 ]
  after=$(cd "$world" && find . -type f -exec sha256sum {} + | sort; find . -printf '%p %T@\n' | sort)
  [ "$before" == "$after" ]
}
