# Pull requests

For `gh pr`/`gh issue` syntax, see the `infra` skill's `github.md` cheat
sheet. This covers only what that sheet doesn't: workflow order and
non-obvious flags.

## Opening

1. Branch off the default branch; never commit to it directly.
2. Rebase onto the current default branch before pushing, so the PR contains
   only your commits: `scripts/rebase-onto-default.sh [--push]` detects the
   default branch, fetches, rebases, and reports what happened (including
   commits dropped as already-applied) in one call instead of the
   fetch/rebase/inspect sequence by hand.
3. `gh pr create` with a body that says what changed and why, and what was
   verified (with the command output that proves it). No AI-attribution
   footer — see [commit-messages.md](commit-messages.md)'s rule; it applies
   to PR bodies the same as commit messages.
4. Keep the atomic commits; do not flatten them when pushing.

## Fixing feedback on your own, unmerged PR

- A fix for something *this PR itself introduced* (a review comment, a bug
  found while iterating): `git commit --fixup=<sha>` targeting the commit
  that introduced it, not a plain new commit. Push normally — no
  `rebase --autosquash` unless asked; the fixups stay as visible commits,
  still honouring the atomic-commit mandate.
- A fix for something that predates this PR (a pre-existing bug noticed in
  passing): a normal commit — it's not part of this PR's history to keep
  legible.
- Keep the PR title and description in sync with the PR's current state
  across review rounds, not just what was true at opening. After fixup
  commits that change scope (new behavior, a rename, a dropped approach),
  update both with `gh pr edit`.

## Merging

- **Try `scripts/merge-onto-default.sh` first.** Needs an open PR (gates
  on its checks via `gh pr checks --watch`, whatever the repo has —
  none assumed). Rebases locally, re-pushes to refresh CI if that moved
  HEAD, waits for checks, then pushes straight to the default branch —
  fast-forward, signatures intact. GitHub auto-marks the PR merged.
  CI wait is often minutes — run in the background or with a raised
  timeout.
- If it's rejected (branch protection requires a PR — the script says
  so plainly), fall back to `gh pr merge --rebase`, or `--merge` if
  rebase merges are disabled. **Never** `--squash`. Ask the user first
  if signed history on the default branch matters for this repo: both
  fallbacks land unsigned regardless of the source commits (GitHub
  limitation) — see [commit-messages.md](commit-messages.md)'s
  "Preserving signatures".

## Reviewing and receiving review

- Reviewing someone else's PR, or your own diff: use the `review` skill.
- Receiving review feedback: verify each point technically before implementing
  it. Agreeing with a wrong suggestion because a reviewer made it is a
  failure mode, not politeness. See
  [pr-review-responses.md](pr-review-responses.md) for watching, replying and
  resolving threads.

## Checks

Run `gh pr checks` (see `infra/github.md`) before asking for a merge. A red
check you believe is unrelated must still be named, not ignored.
