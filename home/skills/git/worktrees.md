# Worktrees

Use a worktree when feature work needs isolation from the current checkout:
long-running changes, anything that would otherwise force you to stash, or
parallel agent sessions on the same repo.

```
git worktree list
git worktree add ../<repo>-<feature> -b <feature>
git worktree remove ../<repo>-<feature>
```

## The trap

Inside a worktree session, editing a file by its **main-repo absolute path**
silently edits the wrong checkout. Every read and write must target the
worktree path. Confirm with `git rev-parse --show-toplevel` before the first
edit of a session and use paths relative to that.

The trap is easy to fall into because exploration hands back main-repo absolute
paths, and reusing one for an edit lands outside the worktree, while shell
commands with relative paths correctly hit the worktree. The result is
split-brain: some changes in each checkout.

To recover, copy the wrongly-edited file into the worktree and revert the
original:

```
cp <main>/path/to/file <worktree>/path/to/file
git -C <main> checkout -- path/to/file
```

Then check both trees are as you expect with `git -C <main> status` and
`git -C <worktree> status` before continuing.

## Housekeeping

- One worktree per branch; `git worktree prune` after deleting directories by
  hand.
- Worktrees share the object store, so they are cheap, but they do **not**
  share untracked files, build outputs, or `.env` files. Anything ignored has
  to be recreated in the new tree.

See also `superpowers:using-git-worktrees` for the full workflow.
