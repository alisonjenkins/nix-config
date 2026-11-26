# 0001. Merge by rebasing locally and pushing, not with GitHub's rebase

- Status: Accepted
- Date: 2026-11-26

## Context

Every commit in these repos is signed, and history is kept linear and
atomic so any one commit can be reverted alone.

GitHub's "Rebase and merge" (`gh pr merge --rebase`, or the button) does
not keep signatures. GitHub's docs say it creates a modified copy of each
commit from the original's data, which GitHub "can't therefore sign"
([about pull request merges](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/about-pull-request-merges)).
The commits land on the default branch unsigned, even when every source
commit was signed.

The 2026-11-26 skills audit found `home/skills/git/SKILL.md` telling agents
to prefer `gh pr merge --rebase`. That contradicts the user's mandate and
the skill's own `pr-workflow.md`, which tries
`scripts/merge-onto-default.sh` first.

## Decision

Merge a branch by rebasing it locally onto the default branch and pushing
the result to the default branch as a fast-forward. The commits keep the
signatures made on the user's machine. `home/skills/git/scripts/merge-onto-default.sh`
does this, after its fixup gate.

Use `gh pr merge --rebase` only when the direct push is rejected, for
example by branch protection. Use `gh pr merge --merge` only when rebase
merges are also unavailable. Never squash.

## Alternatives rejected

- **GitHub's rebase merge as the default.** It drops signatures, as above.
- **Merge commits.** They keep signatures, but add merge commits to the
  history. A linear history is easier to read, bisect and revert one
  commit at a time.
- **Squash merges.** They collapse atomic commits into one, so a single
  change can no longer be reverted alone.

## Consequences

- Merging needs a local checkout and push rights to the default branch.
- A rewritten commit is re-signed locally by the rebase, so signing must
  work on the machine doing the merge. A signing failure is fixed, never
  bypassed.
- The skill only needs to state the order of merge routes and cite this
  record. The reasons live here.

## Evidence

- GitHub docs, linked above, on rebase-and-merge and signature
  verification.
- The user's global `CLAUDE.md` Git Strategy mandate, and the user's
  comment on the 2026-11-26 audit doc confirming the reason.
- `home/skills/git/pr-workflow.md`, "Try `scripts/merge-onto-default.sh`
  first".

## Revisit when

GitHub signs the commits its rebase merge creates, or the default branch
stops accepting direct pushes from the user.
