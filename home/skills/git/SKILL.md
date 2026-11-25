---
name: git
description: >-
  Use when committing, amending, splitting or reordering changes, opening/updating/merging a PR, merge strategy, branching, or worktree setup ("commit this", "push it", "open a PR"). Also: responding to review on your PR (threads, resolve, Copilot re-review, auto-merge), ship this, fixup commits, merge/rebase conflicts, .gitignore vs .git/info/exclude, jj (Jujutsu) in a colocated repo. Not for judging someone else's diff or PR (see review).
metadata:
  summary: "Use for commit, push, PR, merge, rebase, branches, worktrees, review threads on your PR, .gitignore, fixup commits, jj."
---

# Git

## Mandate

- **Atomic commits.** Each commit does exactly one granular thing. Reverting
  that commit alone must leave the project compilable, assuming it compiled
  before. Never bundle unrelated changes into one commit.
- **Never squash.** Squash merges collapse atomic commits into one oversized
  commit and destroy per-change revertability.
- **No `fixup!`/`squash!`/`amend!` commit lands on the default branch.**
  Fixups are fine while a PR is open; they are autosquashed into their
  targets before merge (see [pr-workflow.md](pr-workflow.md)), and
  `scripts/check-no-fixups.sh` must be green before any merge route.
- **Merging PRs and branches:** prefer rebase-and-merge
  (`gh pr merge --rebase`). If rebase merges are unavailable or disallowed,
  use a merge commit (`gh pr merge --merge`). Never `gh pr merge --squash`.
- **Sign every commit.** Never pass `--no-gpg-sign` or `-c commit.gpgsign=false`,
  and never work around a failing signature by disabling it — fix the
  signing setup instead.

User mandates, not preferences: they override any default a tool or another
skill suggests.

| Excuse | Why it doesn't hold |
|---|---|
| "This squash is basically one atomic change already" | Then it was one commit to begin with; squashing elsewhere still destroys other commits' reverts |
| "The user obviously wants this committed" | Confidence isn't the bar — commit only when asked, every time; asking first costs one line |

## Working rules

- Commit or push only when asked. If work lands on the default branch, branch
  first.
- Interactive git (`rebase -i`, `add -i`) is unavailable in agent sessions;
  achieve the same result with non-interactive commands.
- Confirm with the user before amending or rebasing anything already pushed;
  rewriting published history is irreversible for anyone who pulled it.
- Use the `gh` CLI for anything GitHub-side (PRs, issues, API), not the web UI
  and not raw REST where `gh` has a subcommand.
- Repo root has a `.jj/` directory: use jj, per [jj.md](jj.md). Inside a git
  worktree, always git.
- Ignore entries go in the checked-in `.gitignore` by default, so everyone
  gets them. Reserve `.git/info/exclude` for genuinely personal files (a local
  work queue, scratch notes) or when the user asks for a local-only exclude.

## Compact output

Measured (decision 0022): `git diff` and `git show` are most of git's token
cost, and add-then-commit is most of its calls.

- `git diff --stat` (or `--name-only`) first; then `git diff --no-ext-diff -- <path>` for the
  one file you need. Never `git diff | head`: it pays for a cut you then redo.
- `git show --stat <sha>` before `git show <sha> -- <path>`; not
  `git show <sha> | sed -n`.
- `git status -sb`, `git log --oneline -n 10`.
- One call for add and commit: `git commit -m "<msg>" -- <paths>` for
  already-tracked files, or `git add <paths> && git commit -F - <<'EOF'` with
  the message once. Do not follow a commit with `git log` or `git status` to
  confirm; its own output says what landed.
- `git diff --no-ext-diff`: where `diff.external` is set (difftastic here),
  plain `git diff` runs it, and its side-by-side output was 1.1x to 11.7x the
  size of the patch on 8 of 10 recent commits, and is not a patch. `git show`
  and `git log -p` do not run it.

## Routing

| Doing | Read |
|---|---|
| Writing a commit message, splitting a large change | [commit-messages.md](commit-messages.md) |
| Opening, updating, reviewing, or merging a PR | [pr-workflow.md](pr-workflow.md) |
| Watching for review on your PR (starts automatically on PR open), replying to or resolving threads | [pr-review-responses.md](pr-review-responses.md) |
| Triaging a GitHub Copilot review specifically | [copilot-reviews.md](copilot-reviews.md) |
| Running commit → branch → PR → review loop → auto-merge unattended | [auto-ship.md](auto-ship.md) |
| Isolating feature work from the current checkout | [worktrees.md](worktrees.md) |
| Resolving a merge or rebase conflict | [merge-conflicts.md](merge-conflicts.md) |
| Working in a repo with `.jj/`, or colocating one | [jj.md](jj.md) |
| Keeping a fix to someone else's project on your fork and building from it | [carry-a-patch.md](carry-a-patch.md) |
