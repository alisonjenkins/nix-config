---
name: git
description: Use when committing, amending, splitting or reordering changes, opening / updating / reviewing / merging a pull request, choosing a merge strategy, branching, or setting up an isolated worktree, including "commit this", "push it", "open a PR". Also when review lands on your own PR: watching or waiting for a review, answering review comments, replying to or resolving review threads, addressing requested changes from a human or a bot, requesting Copilot re-review, or enabling auto-merge / `gh pr merge --auto`. Also for running the whole commit-branch-PR-review-merge sequence unattended: "ship this", "commit, open a PR, and merge it once it's reviewed". Carries the atomic-commit and never-squash mandate, the commit message format, and routes to commit, PR, review-response, auto-ship and worktree guidance.
---

# Git

## Mandate

- **Atomic commits.** Each commit does exactly one granular thing. Reverting
  that commit alone must leave the project compilable, assuming it compiled
  before. Never bundle unrelated changes into one commit.
- **Never squash.** Squash merges collapse atomic commits into one oversized
  commit and destroy per-change revertability.
- **Merging PRs and branches:** prefer rebase-and-merge
  (`gh pr merge --rebase`). If rebase merges are unavailable or disallowed,
  use a merge commit (`gh pr merge --merge`). Never `gh pr merge --squash`.

These three are user mandates, not preferences. They override any default
workflow a tool or another skill suggests.

## Working rules

- Commit or push only when asked. If work lands on the default branch, branch
  first.
- Interactive git (`rebase -i`, `add -i`) is unavailable in agent sessions;
  achieve the same result with non-interactive commands.
- Before amending or rebasing anything already pushed, confirm with the user;
  rewriting published history is not reversible for anyone who pulled it.
- Use the `gh` CLI for anything GitHub-side (PRs, issues, API), not the web UI
  and not raw REST where `gh` has a subcommand.
- Ignore entries go in the checked-in `.gitignore` by default, so everyone
  working on the repo gets them. Reserve `.git/info/exclude` for genuinely
  personal files, such as a local work queue or scratch notes, or when the
  user asks for a local-only exclude.

## Routing

| Doing | Read |
|---|---|
| Writing a commit message, splitting a large change | [commit-messages.md](commit-messages.md) |
| Opening, updating, reviewing, or merging a PR | [pr-workflow.md](pr-workflow.md) |
| Watching for review on your PR, replying to or resolving threads | [pr-review-responses.md](pr-review-responses.md) |
| Running commit → branch → PR → review loop → auto-merge unattended | [auto-ship.md](auto-ship.md) |
| Isolating feature work from the current checkout | [worktrees.md](worktrees.md) |
