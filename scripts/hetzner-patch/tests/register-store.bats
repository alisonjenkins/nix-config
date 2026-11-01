#!/usr/bin/env bats
# Fixture stores with real-looking nixbase32 hash parts; the script under test
# must print the nix-store --register-validity input for each top-level entry.

HA=0j4k2m8wq1pl6xv3nbz5r7cd9fgh4sy0
HB=1a5b9c3d7f2g8h4j6k0m3n7p1q5r9s2v
HC=2x8y1z9b3c5d7f0g2h4j6k8m1n3p5q7r
HD=3k5m7n9p1q2r4s6v8w0x3y5z7b9c1d3f
HE=9zk4nvb7r2x6m1p8q3w5y0s9c4d2g7h1

setup() {
  script="$BATS_TEST_DIRNAME/../register-store.sh"
  store="$BATS_TEST_TMPDIR/store"
  mkdir -p "$store"
}

@test "entry with no references lists an empty ref count" {
  mkdir -p "$store/${HA}-plain"
  printf 'hello\n' > "$store/${HA}-plain/hello.txt"

  run bash "$script" "$store"

  [ "$status" -eq 0 ]
  expected=$(cat <<EOF
$store/${HA}-plain

0
EOF
)
  [ "$output" = "$expected" ]
}

@test "reference found in file contents" {
  mkdir -p "$store/${HA}-app/bin" "$store/${HB}-lib"
  printf 'exec /nix/store/%s-lib/bin/tool\n' "$HB" > "$store/${HA}-app/bin/run"

  run bash "$script" "$store"

  [ "$status" -eq 0 ]
  expected=$(cat <<EOF
$store/${HA}-app

1
$store/${HB}-lib
$store/${HB}-lib

0
EOF
)
  [ "$output" = "$expected" ]
}

@test "reference found only in a symlink target" {
  mkdir -p "$store/${HA}-sym" "$store/${HB}-lib/bin"
  printf 'no hash here\n' > "$store/${HB}-lib/bin/tool"
  ln -s "$store/${HB}-lib/bin/tool" "$store/${HA}-sym/link"

  run bash "$script" "$store"

  [ "$status" -eq 0 ]
  expected=$(cat <<EOF
$store/${HA}-sym

1
$store/${HB}-lib
$store/${HB}-lib

0
EOF
)
  [ "$output" = "$expected" ]
}

@test "self reference is included" {
  mkdir -p "$store/${HA}-self/bin"
  printf 'self=%s-self\n' "$HA" > "$store/${HA}-self/bin/run"

  run bash "$script" "$store"

  [ "$status" -eq 0 ]
  expected=$(cat <<EOF
$store/${HA}-self

1
$store/${HA}-self
EOF
)
  [ "$output" = "$expected" ]
}

@test "hash that matches no store entry is ignored" {
  mkdir -p "$store/${HA}-plain"
  printf 'dangling=%s-gone\n' "$HD" > "$store/${HA}-plain/notes"

  run bash "$script" "$store"

  [ "$status" -eq 0 ]
  expected=$(cat <<EOF
$store/${HA}-plain

0
EOF
)
  [ "$output" = "$expected" ]
}

@test ".links directory and *.lock files are skipped" {
  mkdir -p "$store/.links/${HD}" "$store/${HA}-app"
  printf 'x\n' > "$store/.links/${HD}/file"
  printf 'x\n' > "$store/${HB}-lib.lock"
  printf 'uses %s-lib\n' "$HB" > "$store/${HA}-app/notes"

  run bash "$script" "$store"

  [ "$status" -eq 0 ]
  expected=$(cat <<EOF
$store/${HA}-app

0
EOF
)
  [ "$output" = "$expected" ]
}

@test "multiple references are listed sorted, not in discovery order" {
  mkdir -p "$store/${HA}-app" "$store/${HB}-b" "$store/${HC}-c"
  printf '%s-c then %s-b\n' "$HC" "$HB" > "$store/${HA}-app/run"

  run bash "$script" "$store"

  [ "$status" -eq 0 ]
  expected=$(cat <<EOF
$store/${HA}-app

2
$store/${HB}-b
$store/${HC}-c
$store/${HB}-b

0
$store/${HC}-c

0
EOF
)
  [ "$output" = "$expected" ]
}

@test "output is byte-exact for a two-entry store" {
  mkdir -p "$store/${HA}-app" "$store/${HB}-lib"
  printf 'ref %s-lib\n' "$HB" > "$store/${HA}-app/run"
  cat > "$BATS_TEST_TMPDIR/expected" <<EOF
$store/${HA}-app

1
$store/${HB}-lib
$store/${HB}-lib

0
EOF

  bash "$script" "$store" > "$BATS_TEST_TMPDIR/actual"

  cmp "$BATS_TEST_TMPDIR/expected" "$BATS_TEST_TMPDIR/actual"
}

@test "missing STORE_DIR exits non-zero; stderr names the path, stdout is empty" {
  missing="$BATS_TEST_TMPDIR/does-not-exist"

  run --separate-stderr bash "$script" "$missing"

  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"register-store"* ]]
  [[ "$stderr" == *"$missing"* ]]
  [[ "$stderr" == *"usage: register-store.sh"* ]]
}

@test "nested directories inside an entry are scanned" {
  mkdir -p "$store/${HA}-app/lib/deep/dir" "$store/${HB}-lib"
  printf '%s-lib\n' "$HB" > "$store/${HA}-app/lib/deep/dir/file"

  run bash "$script" "$store"

  [ "$status" -eq 0 ]
  expected=$(cat <<EOF
$store/${HA}-app

1
$store/${HB}-lib
$store/${HB}-lib

0
EOF
)
  [ "$output" = "$expected" ]
}

@test "binary file containing the hash is detected" {
  mkdir -p "$store/${HA}-app/bin" "$store/${HB}-lib"
  printf '\x7f\x45\x4c\x46\x00\x01\x02%s-lib\x00\xff\xfe' "$HB" > "$store/${HA}-app/bin/elf"

  run bash "$script" "$store"

  [ "$status" -eq 0 ]
  expected=$(cat <<EOF
$store/${HA}-app

1
$store/${HB}-lib
$store/${HB}-lib

0
EOF
)
  [ "$output" = "$expected" ]
}

@test "top-level symlink entry contributes only its own target, not the followed content" {
  mkdir -p "$store/${HB}-lib" "$store/${HC}-x"
  printf '%s-x\n' "$HC" > "$store/${HB}-lib/file"
  ln -s "$store/${HB}-lib" "$store/${HE}-link"

  run bash "$script" "$store"

  [ "$status" -eq 0 ]
  expected=$(cat <<EOF
$store/${HB}-lib

1
$store/${HC}-x
$store/${HC}-x

0
$store/${HE}-link

1
$store/${HB}-lib
EOF
)
  [ "$output" = "$expected" ]
}

@test "dangling top-level symlink is listed with no references and does not abort" {
  ln -s "/nonexistent/${HD}-gone" "$store/${HA}-dangling"

  run bash "$script" "$store"

  [ "$status" -eq 0 ]
  expected=$(cat <<EOF
$store/${HA}-dangling

0
EOF
)
  [ "$output" = "$expected" ]
}

@test "unreadable file inside an entry fails the run and names the path" {
  [ "$(id -u)" -ne 0 ] || skip "root reads mode-000 files; cannot provoke a read error"
  mkdir -p "$store/${HA}-app"
  printf 'x\n' > "$store/${HA}-app/secret"
  chmod 000 "$store/${HA}-app/secret"

  run --separate-stderr bash "$script" "$store"

  [ "$status" -ne 0 ]
  [[ "$stderr" == *"$store/${HA}-app/secret"* ]]
}

@test "script run over stdin (the ssh bash -s form) matches a direct run" {
  mkdir -p "$store/${HA}-app" "$store/${HB}-lib"
  printf 'ref %s-lib\n' "$HB" > "$store/${HA}-app/run"
  bash "$script" "$store" > "$BATS_TEST_TMPDIR/direct"

  bash -s -- "$store" < "$script" > "$BATS_TEST_TMPDIR/stdin"

  cmp "$BATS_TEST_TMPDIR/direct" "$BATS_TEST_TMPDIR/stdin"
}
