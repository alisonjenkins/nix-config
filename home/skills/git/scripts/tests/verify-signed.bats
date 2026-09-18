#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../verify-signed.sh"
  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo"
  cd "$repo"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Real SSH commit signing, no agent: a local private key file as
  # user.signingkey makes git shell out to ssh-keygen directly.
  ssh-keygen -t ed25519 -N "" -f "$BATS_TEST_TMPDIR/key" -q
  git config gpg.format ssh
  git config user.signingkey "$BATS_TEST_TMPDIR/key"
  git config gpg.ssh.program ssh-keygen

  # Base commit so later ranges (base..HEAD) don't need a parent of the
  # repo's very first commit, which doesn't exist.
  echo base >base.txt
  git add base.txt
  git commit -q --no-gpg-sign -m base
  base_sha="$(git rev-parse HEAD)"
}

commit_signed() {
  echo "$RANDOM" >file.txt
  git add file.txt
  git commit -q -S -m "$1"
}

commit_unsigned() {
  echo "$RANDOM" >file.txt
  git add file.txt
  git commit -q --no-gpg-sign -m "$1"
}

@test "no args prints usage and exits 1" {
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "invalid rev-range errors clearly" {
  run "$script" "not-a-real-ref..HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a valid rev-range"* ]]
}

@test "empty range reports no commits and exits 0" {
  commit_signed "first"
  run "$script" "HEAD..HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no commits in range"* ]]
}

@test "a fully signed range reports SIGNED for each commit and exits 0" {
  commit_signed "first"
  commit_signed "second"
  run "$script" "$base_sha..HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIGNED"*"first"* ]]
  [[ "$output" == *"SIGNED"*"second"* ]]
  [[ "$output" != *"UNSIGNED"* ]]
}

@test "an unsigned commit in range is reported and exit is 1" {
  commit_signed "first"
  commit_unsigned "second"
  run "$script" "$base_sha..HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNSIGNED"*"second"* ]]
  [[ "$output" == *"1 commit(s) unsigned"* ]]
}

@test "multiple unsigned commits are all reported" {
  commit_unsigned "first"
  commit_unsigned "second"
  run "$script" "$base_sha..HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNSIGNED"*"first"* ]]
  [[ "$output" == *"UNSIGNED"*"second"* ]]
  [[ "$output" == *"2 commit(s) unsigned"* ]]
}
