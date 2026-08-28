# Reviewing a pull request

## Resolving the target

A PR number given by the user always wins over the checked-out branch. With no
number, take the branch's PR:

```
gh pr view --json number,title,url,headRefName,baseRefName,state
```

If neither resolves, ask which PR. Do not guess.

## Reading it

```
gh pr view <number> --json title,body,files,reviews,mergeable,statusCheckRollup
gh pr diff <number>
gh pr checks <number>
```

Read the PR description first, then the diff against it. A diff that does more
than the description claims is a finding regardless of code quality.

If the description references an issue, read the issue and review against what
it actually asked for. A correct implementation of the wrong requirement is a
finding.

Open the full files around any non-trivial hunk. A diff hides the callers, the
helper that already does this, and the convention the surrounding code follows,
which is where most real findings come from.

Static review by default. Do not run tests, builds, formatters or linters, and
do not edit files, unless the user asked for that in this request.

## Commit structure

Check the commit series, not only the net diff:

```
gh pr view <number> --json commits --jq '.commits[].messageHeadline'
```

Each commit should be atomic and individually revertable. A series where the
middle commits do not build is a finding because it defeats bisection.

## Posting comments

- One comment per finding, anchored to the exact line.
- Severity-ordered; lead with correctness.
- Distinguish blocking from optional explicitly. An unlabelled nit reads as a
  blocker and wastes a round trip.
- Approve, request changes, or comment; do not leave a review ambiguous.

```
gh pr review <number> --comment --body "..."
gh pr review <number> --request-changes --body "..."
```

Findings are prose someone else reads, so apply the `writing` skill before
posting. The tells this kind of text attracts: "it is important to note that",
"this ensures", stacked hedges, a bold label that restates the line, and a
sycophantic opener on the verdict.

## Pre-review mode

When the user asks for a pre-review, a dry run, or a look before they request
review, report in chat and post nothing. Never run `gh pr review` or
`gh pr comment` in this mode, not even for a finding you are certain of.

Group by **Blocking**, **Should fix**, **Nit**. Per finding give the clickable
`file_path:line`, one sentence on the problem, the concrete failure it causes,
and the fix. Write each one so the user can paste it into a PR comment under
their own name without editing it. Close with a one-line verdict. If nothing of
substance is wrong, say that instead of padding the list.
