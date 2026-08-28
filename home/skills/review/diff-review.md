# Reviewing a diff

## Getting the diff

```
git diff                 # unstaged
git diff --staged        # staged
git diff <base>...HEAD   # whole branch against its base
```

Review the **whole** diff, including files you did not expect to change.
Generated files, lockfiles, and formatting churn hide real changes; if they are
mixed into a logic commit, that is itself a finding (see the `git` skill).

## Order of passes

1. Read the diff once for intent: what is this change supposed to do?
2. Read each hunk against that intent. Anything that does not serve it is
   either scope creep or a bug.
3. Read the *surroundings* of each hunk. Most real defects are in the
   interaction with unchanged code, not inside the new lines.
4. Ask what is missing: the error path, the test, the caller that also needed
   updating.

## Reviewing your own work

The same rubric, with one addition: check that you actually ran the
verification you are about to claim. Quote the command output. If a step was
skipped, say which and why; see `superpowers:verification-before-completion`.
