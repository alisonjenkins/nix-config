#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../detect-inputs.sh"
  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo"
  bash_bin="$(command -v bash)"
  # Isolated PATH so a tack installed on the host never leaks into a result.
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  ln -s "$(command -v grep)" "$bin/grep"
  if command -v jq >/dev/null; then ln -s "$(command -v jq)" "$bin/jq"; fi
}

run_detect() {
  PATH="$bin" run "$bash_bin" "$script" "$@"
}

field() {
  local key="$1"
  [[ "$output" =~ \"$key\":\"?([^\",}]*) ]] || return 1
  echo "${BASH_REMATCH[1]}"
}

write_lock() {
  cat >"$repo/flake.lock" <<'JSON'
{"nodes":{"nixpkgs":{"locked":{"rev":"abc"}},"root":{"inputs":{"nixpkgs":"nixpkgs"}}},"root":"root","version":7}
JSON
}

write_root_only_lock() {
  echo '{"nodes":{"root":{}},"root":"root","version":7}' >"$repo/flake.lock"
}

write_tack() {
  mkdir -p "$repo/.tack"
  echo '[nixpkgs]' >"$repo/.tack/pins.toml"
}

fake_tack() {
  # Builtins only: the isolated PATH has no cat.
  printf '#!%s\nprintf "%%s\\n" "Commands:" %q\n' "$bash_bin" "$1" >"$bin/tack"
  chmod +x "$bin/tack"
}

@test "plain flake with a populated lock is mode flake" {
  echo '{ inputs.nixpkgs.url = "github:NixOS/nixpkgs"; outputs = _: {}; }' >"$repo/flake.nix"
  write_lock
  run_detect "$repo"
  [ "$status" -eq 0 ]
  [ "$(field mode)" = flake ]
  [ "$(field flake_lock_nodes)" = 1 ]
  [ "$(field update)" = "nix flake update NAME" ]
}

@test "flake.nix without a lock yet is still mode flake" {
  echo '{ outputs = _: {}; }' >"$repo/flake.nix"
  run_detect "$repo"
  [ "$status" -eq 0 ]
  [ "$(field mode)" = flake ]
  [ "$(field flake_lock)" = false ]
}

@test "tack flake with a root-only lock is mode tack" {
  echo '{ outputs = args: let inputs = (import ./.tack) { }; in {}; }' >"$repo/flake.nix"
  write_root_only_lock
  write_tack
  run_detect "$repo"
  [ "$status" -eq 0 ]
  [ "$(field mode)" = tack ]
  [ "$(field flake_lock_nodes)" = 0 ]
  [ "$(field flake_imports_tack)" = true ]
  [ "$(field update)" = "tack update NAME" ]
}

@test "tack without any flake is mode tack" {
  write_tack
  run_detect "$repo"
  [ "$status" -eq 0 ]
  [ "$(field mode)" = tack ]
  [ "$(field flake_nix)" = false ]
}

@test "tack beside a populated flake.lock is mode both" {
  echo '{ inputs.nixpkgs.url = "github:NixOS/nixpkgs"; outputs = _: {}; }' >"$repo/flake.nix"
  write_lock
  write_tack
  run_detect "$repo"
  [ "$status" -eq 0 ]
  [ "$(field mode)" = both ]
  [ "$(field flake_imports_tack)" = false ]
  [[ "$output" == *"tack update NAME for tack pins"* ]]
}

@test "empty directory is mode none" {
  run_detect "$repo"
  [ "$status" -eq 0 ]
  [ "$(field mode)" = none ]
  [ "$(field update)" = "" ]
}

@test "a .tack dir without pins.toml is not tack" {
  mkdir -p "$repo/.tack"
  run_detect "$repo"
  [ "$(field mode)" = none ]
  [ "$(field tack)" = false ]
}

@test "defaults to the current directory" {
  write_tack
  cd "$repo"
  run_detect
  [ "$status" -eq 0 ]
  [ "$(field mode)" = tack ]
}

@test "counts lock nodes without jq" {
  rm -f "$bin/jq"
  write_lock
  run_detect "$repo"
  [ "$status" -eq 0 ]
  [ "$(field flake_lock_nodes)" = 1 ]
  [ "$(field mode)" = flake ]
}

@test "counts a root-only lock as zero nodes without jq" {
  rm -f "$bin/jq"
  write_root_only_lock
  write_tack
  run_detect "$repo"
  [ "$status" -eq 0 ]
  [ "$(field flake_lock_nodes)" = 0 ]
  [ "$(field mode)" = tack ]
}

@test "counts every node of a one-line lock without jq" {
  rm -f "$bin/jq"
  echo '{"nodes":{"a":{"locked":{"rev":"1"}},"b":{"locked":{"rev":"2"}},"c":{"locked":{"rev":"3"}},"root":{}},"root":"root","version":7}' >"$repo/flake.lock"
  run_detect "$repo"
  [ "$status" -eq 0 ]
  [ "$(field flake_lock_nodes)" = 3 ]
}

@test "fails instead of reporting zero nodes when the lock is unreadable without jq" {
  rm -f "$bin/jq"
  write_lock
  chmod 000 "$repo/flake.lock"
  run_detect "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot read"* ]]
}

@test "treats a tack whose --help fails as v1" {
  printf '#!%s\nexit 1\n' "$bash_bin" >"$bin/tack"
  chmod +x "$bin/tack"
  run_detect "$repo"
  [ "$status" -eq 0 ]
  [ "$(field tack_cli)" = v1 ]
}

@test "reports tack_cli none when tack is not on PATH" {
  run_detect "$repo"
  [ "$(field tack_cli)" = none ]
}

@test "reports tack_cli v1 for a CLI without the 2.x commands" {
  fake_tack '  init    scaffold
  update  fetch pins'
  run_detect "$repo"
  [ "$(field tack_cli)" = v1 ]
}

@test "reports tack_cli v2 when the CLI lists verify" {
  fake_tack '  update  fetch pins
  verify  check signatures'
  run_detect "$repo"
  [ "$(field tack_cli)" = v2 ]
}

@test "rejects a missing directory" {
  run_detect "$repo/nope"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a directory"* ]]
}

@test "rejects more than one argument" {
  run_detect a b
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}
