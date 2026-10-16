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
5. Check spec adherence separately from correctness: is this actually what
   was asked — the `requirements` skill's one-sentence problem statement, or
   the PR description — no more and no less? A diff can be correct for its
   inputs and still solve the wrong problem, or the right one plus an
   unrequested rewrite alongside it; that's easy to miss when it's folded
   into Correctness or Scope instead of checked on its own.

## Reviewing your own work

The same rubric, with one addition: check that you actually ran the
verification you are about to claim. Quote the command output. If a step was
skipped, say which and why — see `testing`'s "Verification before claiming
completion".

- **Review before you push or open the PR**, not after. Findings found on an open PR cost
  a force-push and a rewritten description.
- **Review the prose as well as the code.** Every factual claim in a commit message, PR body,
  comment or skill text needs the evidence behind it. "Nothing reads X", "saves N" and "matches"
  are the usual overreach: write what you observed and what you did not check.
- **Check every consumer of what you changed.** A skill linked into several agents' directories,
  a module option read by several hosts, a shared file other branches also edit.
- **For a fix someone else wrote, an agent included, run the original failing case** and ask
  whether it removes the failure or only shrinks it. Scaling scores to the best match
  shrinks a noise problem; the top hit still always passes.
