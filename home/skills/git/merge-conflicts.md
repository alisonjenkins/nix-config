# Merge conflicts

A conflict is two commits disagreeing about the same lines, not a prompt to
pick a side. Resolve to the intent of both.

## Resolving

1. For each conflicted hunk, find the commit that introduced each side:
   `git log -p -- <file>` on the base and on the incoming branch, or `git
   blame` the pre-conflict version.
2. Understand what each side was *trying to do*, not just what it changed.
   Two edits to the same function are often both needed.
3. Write the resolution that satisfies both intents. Only take one side
   wholesale when the other is genuinely superseded — say so in the
   resolution, don't do it silently.
4. Re-run the build and the relevant tests on the resolved state before
   continuing the rebase or merge; a conflict resolution is unreviewed code
   until verified.
5. If the two sides solve the same problem two incompatible ways, that's a
   decision for the user, not a coin flip — stop and ask.

## In this repo's flow

This skill's `scripts/rebase-onto-default.sh` (resolved relative to wherever
this file lives — this repo's `home/skills/git/scripts/`, or the deployed
`~/.claude/skills/git/scripts/` — not your shell's cwd) stops with the
conflicted paths still marked and does not guess at a resolution. After
resolving by hand: `git add <files>`, then `git rebase --continue`. Never
default to `git checkout --ours`/`--theirs` — it silently drops one side's
intent instead of reconciling it.
