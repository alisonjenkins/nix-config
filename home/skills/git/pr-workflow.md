# Pull requests

## Opening

1. Branch off the default branch; never commit to it directly.
2. Rebase onto the current default branch before pushing, so the PR contains
   only your commits.
3. `gh pr create` with a body that says what changed and why, and what was
   verified (with the command output that proves it).
4. Keep the atomic commits — do not flatten them when pushing.

## Merging

- `gh pr merge --rebase` first choice.
- `gh pr merge --merge` when rebase merges are disabled on the repo.
- **Never** `gh pr merge --squash`.

## Reviewing and receiving review

- Reviewing someone else's PR, or your own diff: use the `review` skill.
- Receiving review feedback: verify each point technically before implementing
  it. Agreeing with a wrong suggestion because it came from a reviewer is a
  failure mode, not politeness. See `superpowers:receiving-code-review`.

## Checks

`gh pr checks <number>` before asking for a merge. A red check that you believe
is unrelated still needs to be named explicitly, not ignored.
