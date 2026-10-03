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
5. **Start the review watch immediately after `gh pr create` succeeds** —
   don't wait to be told, and don't ask first. Run
   `scripts/pr-status.sh <number> [owner/repo]` once first and triage
   whatever it shows (`watch-pr.sh` never reports state that exists on its
   first tick, so an instant Copilot auto-review would otherwise be missed),
   then launch the watch as described in "Watching for a review" in
   [pr-review-responses.md](pr-review-responses.md), passing the review
   count you triaged as `WATCH_PR_TRIAGED_REVIEWS`. Tell the user it is
   running. Skip only if the user said not to watch this PR. This applies to
   a PR opened by any route, including one delegated to the `pr-creator`
   agent: a sub-agent's background task dies with it, so the agent that
   receives its report starts the watch itself.

## Fixing feedback on your own, unmerged PR

- A fix for something *this PR itself introduced* (a review comment, a bug
  found while iterating): `git commit --fixup=<sha>` targeting the commit
  that introduced it, not a plain new commit. Push normally — while the PR is
  open the fixups stay as visible commits, so reviewers can see what changed
  since they last looked; no `rebase --autosquash` mid-review unless asked.
- **A `fixup!` commit must never reach the default branch.** It is a
  placeholder for "fold me into my target", not a change that stands alone:
  landed as-is it is non-atomic (reverting the target leaves the fix
  behind) and its subject is unreadable in `git log`. The fold happens at
  merge time, once review is done:
  `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/<default>` (the
  empty sequence editor makes it non-interactive), then
  `git push --force-with-lease`. This is not "squash" in the mandate's
  sense: each fixup merges into exactly one named target, every other
  commit survives, and atomic commits are the result, not the casualty.
  Also covers `squash!` and `amend!`.
- The guard is `scripts/check-no-fixups.sh [range]` (default
  `origin/<default>..HEAD`; exits 1 and names each offender).
  `scripts/merge-onto-default.sh` runs it before touching anything, so the
  preferred merge route cannot land a fixup. **`gh pr merge --rebase` /
  `--merge` and the GitHub UI have no such gate** — run the script yourself
  immediately before either fallback, and never merge with it red.
- A fix for something that predates this PR (a pre-existing bug noticed in
  passing): a normal commit — it's not part of this PR's history to keep
  legible.
- Keep the PR title and description in sync with the PR's current state
  across review rounds, not just what was true at opening. After fixup
  commits that change scope (new behavior, a rename, a dropped approach):
  `scripts/pr-description.sh pull <number>` writes the current title/body
  to local files (under `.git/`, not the repo tree) so editing the body is
  an Edit-tool diff, not retyping the whole description into a `gh pr edit`
  heredoc; `scripts/pr-description.sh push <number>` writes both back via
  `--body-file`.

## Merging

- **Before any merge route: no `fixup!`/`squash!`/`amend!` commits in the
  PR** (see "Fixing feedback" above). If `check-no-fixups.sh` is red,
  autosquash and re-push first; the merge script stops on it by itself.
- **Try `scripts/merge-onto-default.sh` first.** Needs an open PR (gates
  on its checks via `gh pr checks --watch`, whatever the repo has —
  none assumed). Refuses if fixup commits remain. Rebases locally, re-pushes to refresh CI if that moved
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
