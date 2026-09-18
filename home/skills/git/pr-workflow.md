# Pull requests

For `gh pr`/`gh issue` command syntax, see the `infra` skill's `github.md`
cheat sheet. Below covers only what that sheet doesn't: the workflow order and
the non-obvious flags.

## Opening

1. Branch off the default branch; never commit to it directly.
2. Rebase onto the current default branch before pushing, so the PR contains
   only your commits.
3. `gh pr create` with a body that says what changed and why, and what was
   verified (with the command output that proves it). No AI-attribution
   footer — see [commit-messages.md](commit-messages.md)'s rule; it applies
   to PR bodies the same as commit messages.
4. Keep the atomic commits; do not flatten them when pushing.

## Fixing feedback on your own, unmerged PR

- When the fix addresses something *this PR itself introduced* (a review
  comment, a bug you find while iterating), commit it as
  `git commit --fixup=<sha>` targeting the commit that introduced it, not a
  plain new commit. Push normally — do not `rebase --autosquash` unless
  asked; the fixups stay as their own visible commits, still reflecting the
  atomic-commit mandate.
- If the fix addresses something that predates this PR (a pre-existing bug
  you noticed in passing), use a normal commit instead — it's not part of
  this PR's own history to keep legible.
- Keep the PR title and description in sync with the PR's actual current
  state as it evolves across review rounds — not just what was true when it
  was opened. After a round of fixup commits that changes scope (new
  behavior, a renamed thing, a dropped approach), update both with
  `gh pr edit`.

## Merging

- `gh pr merge --rebase` first choice.
- `gh pr merge --merge` when rebase merges are disabled on the repo.
- **Never** `gh pr merge --squash`.

## Reviewing and receiving review

- Reviewing someone else's PR, or your own diff: use the `review` skill.
- Receiving review feedback: verify each point technically before implementing
  it. Agreeing with a wrong suggestion because it came from a reviewer is a
  failure mode, not politeness. See `superpowers:receiving-code-review`, and
  [pr-review-responses.md](pr-review-responses.md) for watching, replying and
  resolving threads.

## Checks

Run `gh pr checks` (see `infra/github.md`) before asking for a merge. A red
check that you believe is unrelated still needs to be named explicitly, not
ignored.
