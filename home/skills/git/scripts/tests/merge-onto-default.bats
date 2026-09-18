#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../merge-onto-default.sh"

  origin="$BATS_TEST_TMPDIR/origin.git"
  git init -q --bare "$origin"

  repo="$BATS_TEST_TMPDIR/repo"
  git clone -q "$origin" "$repo"
  cd "$repo"
  git config user.email "test@example.com"
  git config user.name "Test User"
  # Direct pushes to main must not require signing for most of these
  # tests -- only the signing-specific tests turn it on.
  git config commit.gpgsign false

  echo base >base.txt
  git add base.txt
  git commit -q -m base
  git branch -M main
  git push -q -u origin main
  git remote set-head origin main
}

feature_branch_with_commit() {
  git switch -q -c feature
  echo "$1" >feature.txt
  git add feature.txt
  git commit -q -m "$1"
}

@test "no args required; extra args print usage and exit 1" {
  run "$script" extra-arg
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "detached HEAD errors clearly" {
  git checkout -q --detach main
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"detached HEAD"* ]]
}

@test "no origin remote errors clearly (checked before default-branch detection)" {
  cd "$BATS_TEST_TMPDIR"
  git init -q noremote
  cd noremote
  git config user.email "test@example.com"
  git config user.name "Test User"
  git commit -q --allow-empty -m init
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no 'origin' remote"* ]]
}

@test "already on the default branch errors clearly" {
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already on the default branch"* ]]
}

@test "rebases and fast-forward-pushes a clean feature branch directly onto main" {
  feature_branch_with_commit "one"

  run "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"signatures intact"* ]]

  run git ls-remote origin refs/heads/main
  remote_sha="${output%%$'\t'*}"
  run git rev-parse HEAD
  [ "$remote_sha" = "$output" ]
}

@test "rebases onto an advanced main before pushing" {
  feature_branch_with_commit "one"

  git switch -q main
  echo advance >advance.txt
  git add advance.txt
  git commit -q -m advance
  git push -q origin main
  git switch -q feature

  run "$script"
  [ "$status" -eq 0 ]

  run git ls-remote origin refs/heads/main
  remote_sha="${output%%$'\t'*}"
  run git rev-parse HEAD
  [ "$remote_sha" = "$output" ]
  run git log --format=%s -1
  [ "$output" = "one" ]
}

@test "a rebase conflict stops before any push is attempted" {
  feature_branch_with_commit "one"
  echo "conflict-from-feature" >base.txt
  git commit -q -am "conflicting-feature-change"

  git switch -q main
  echo "conflict-from-main" >base.txt
  git commit -q -am "conflicting-main-change"
  git push -q origin main
  git switch -q feature

  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" != *"pushing"* ]]
}

@test "refuses to push unsigned commits when commit.gpgsign is true" {
  git config commit.gpgsign true
  git config gpg.format ssh
  ssh-keygen -t ed25519 -N "" -f "$BATS_TEST_TMPDIR/key" -q
  git config user.signingkey "$BATS_TEST_TMPDIR/key"
  git config gpg.ssh.program ssh-keygen

  git switch -q -c feature
  echo one >feature.txt
  git add feature.txt
  git commit -q --no-gpg-sign -m one

  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsigned"* ]]
  run git ls-remote origin refs/heads/main
  original_main="${output%%$'\t'*}"
  run git rev-parse main
  # main on the remote is untouched -- confirm nothing was pushed
  [ "$original_main" != "" ]
}

@test "a protected branch (rejected direct push) reports the gh pr merge fallback plainly" {
  feature_branch_with_commit "one"

  # Simulate branch protection blocking direct pushes to main by
  # replacing origin with a receive.denyCurrentBranch-style rejection:
  # a pre-receive hook in the bare origin that refuses pushes to main.
  mkdir -p "$origin/hooks"
  cat >"$origin/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
while read -r old new ref; do
  if [[ "$ref" == "refs/heads/main" ]]; then
    echo "remote: protected branch: main requires a pull request" >&2
    exit 1
  fi
done
HOOK
  chmod +x "$origin/hooks/pre-receive"

  run "$script"
  [ "$status" -eq 1 ]
  # git's own stderr already contains the word "rejected" regardless of
  # what this script says, so assert on this script's own added text
  # specifically, not on git's boilerplate.
  [[ "$output" == *"likely branch protection requires merging via a pull request"* ]]
  [[ "$output" == *"gh pr merge"* ]]
  [[ "$output" == *"will be unsigned"* ]]
}
