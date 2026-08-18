# Reviewing a pull request

## Reading it

```
gh pr view <number> --json title,body,files,reviews,mergeable,statusCheckRollup
gh pr diff <number>
gh pr checks <number>
```

Read the PR description first, then the diff against it. A diff that does more
than the description claims is a finding regardless of code quality.

## Commit structure

Check the commit series, not only the net diff:

```
gh pr view <number> --json commits --jq '.commits[].messageHeadline'
```

Each commit should be atomic and individually revertable. A series where the
middle commits do not build is a finding — it defeats bisection.

## Posting comments

- One comment per finding, anchored to the exact line.
- Severity-ordered; lead with correctness.
- Distinguish blocking from optional explicitly. An unlabelled nit reads as a
  blocker and wastes a round trip.
- Approve, request changes, or comment — do not leave a review ambiguous.

```
gh pr review <number> --comment --body "..."
gh pr review <number> --request-changes --body "..."
```
