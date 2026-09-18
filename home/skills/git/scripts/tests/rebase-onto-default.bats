#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../rebase-onto-default.sh"

  origin="$BATS_TEST_TMPDIR/origin.git"
  git init -q --bare "$origin"

  repo="$BATS_TEST_TMPDIR/repo"
  git clone -q "$origin" "$repo"
  cd "$repo"
  git config user.email "test@example.com"
  git config user.name "Test User"

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

@test "no origin remote errors clearly" {
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

@test "not a git repository errors clearly" {
  cd "$BATS_TEST_TMPDIR"
  mkdir plain && cd plain
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not inside a git repository"* ]]
}

@test "detached HEAD errors clearly" {
  git checkout -q --detach main
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"detached HEAD"* ]]
}

@test "already on the default branch errors clearly" {
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already on the default branch"* ]]
}

@test "unknown flag prints usage and exits 1" {
  feature_branch_with_commit "one"
  run "$script" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "rebases a feature branch cleanly onto an advanced default branch" {
  feature_branch_with_commit "feature-work"

  git switch -q main
  echo "main-advance" >main2.txt
  git add main2.txt
  git commit -q -m "main-advance"
  git push -q origin main
  git switch -q feature

  run "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rebasing feature onto origin/main"* ]]
  [[ "$output" == *"1 commit(s) ahead of origin/main"* ]]
  run git log --format=%s -1
  [ "$output" = "feature-work" ]
  run git merge-base --is-ancestor origin/main HEAD
  [ "$status" -eq 0 ]
}

@test "reports commits dropped as already applied upstream" {
  # git only prints the "skipped previously applied" warning when at
  # least one commit remains to replay after the drop(s) -- an
  # all-dropped rebase takes a silent fast-path instead. Mirror the
  # real shape: one already-merged commit plus one genuinely new one.
  feature_branch_with_commit "shared-change"
  echo "still-new" >still-new.txt
  git add still-new.txt
  git commit -q -m "still-new"

  # Simulate the PR for "shared-change" having already merged to main
  # under a different message (e.g. a rebase-merge server-side rewrite,
  # same as this session's own PR #321/#322) by applying the identical
  # diff on main with a different commit message: same patch-id, but a
  # genuinely distinct commit object — a same-message/same-parent/same-
  # timestamp repeat would collide into the literal same SHA instead
  # and not exercise the by-SHA skip-detection at all.
  git switch -q main
  echo "shared-change" >feature.txt
  git add feature.txt
  git commit -q -m "shared-change (rebase-merged)"
  echo "more" >main3.txt
  git add main3.txt
  git commit -q -m "main-more"
  git push -q origin main
  git switch -q feature

  run "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dropped as already applied"* ]]
  [[ "$output" == *"1 commit(s) ahead"* ]]
  run git log --format=%s -1
  [ "$output" = "still-new" ]
}

@test "--push force-pushes the branch after a clean rebase" {
  feature_branch_with_commit "one"
  git push -q -u origin feature

  git switch -q main
  echo "main-advance" >main2.txt
  git add main2.txt
  git commit -q -m "main-advance"
  git push -q origin main
  git switch -q feature

  run "$script" --push
  [ "$status" -eq 0 ]
  [[ "$output" == *"pushing"* ]]
  run git rev-parse feature
  local_sha="$output"
  run git ls-remote origin refs/heads/feature
  [[ "$output" == "$local_sha"* ]]
}

@test "a real conflict stops the rebase and reports it instead of leaving it silent" {
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
  [[ "$output" == *"conflict"* ]]
  run git status --porcelain=v1 -z --branch
  [[ "$output" == *"rebase"* ]] || {
    [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]
  }
}

@test "falls back to probing origin for main when origin/HEAD isn't set" {
  git remote set-head origin --delete
  feature_branch_with_commit "one"
  run "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"onto origin/main"* ]]
}

@test "errors clearly when no default branch can be determined" {
  git remote set-head origin --delete
  # rename the only branch away from any of the probed candidate names
  git switch -q main
  git branch -m main trunk-but-not-a-probed-name
  git push -q origin :main
  git push -q -u origin trunk-but-not-a-probed-name
  feature_branch_with_commit "one"
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"couldn't determine the default branch"* ]]
}
