# Responding to review on your own PR

Covers the receiving end: watching for a review to land, answering each
thread, fixing what is real, and resolving threads. For *giving* a review, use
the `review` skill.

A fixed finding is not a closed finding. Fixing the code addresses the
defect; replying addresses the review — every wave, before moving on, never
"fix now, reply later." Resolving is not automatic with the reply: resolve
only once the point is settled (see "Resolving threads" below), and leave a
thread you disagree with open until the reviewer closes it. A multi-wave
polling loop (bot reviewers re-review after every push) makes the reply step
easy to miss, because nothing breaks: tests pass, the branch looks green. The
backlog is invisible until someone opens the PR's Conversation tab and finds
un-replied-to threads behind commits that already fixed them. If you catch
yourself fixing a second wave without having replied to the first, stop and
close out the backlog first.

## Watching for a review

There is no push notification for a review; poll. Ask before starting a long
watch, and say what interval you chose.

```
gh pr view <number> --json reviewDecision,reviews,statusCheckRollup
gh pr checks <number> --watch          # checks only, blocks until they settle
```

`reviewDecision` is `APPROVED`, `CHANGES_REQUESTED`, `REVIEW_REQUIRED`, or
`null` when no review is required. It does **not** change when a reviewer
leaves unresolved line comments without a verdict, so poll the thread list
too (below), not `reviewDecision` alone.

Poll on the order of minutes, not seconds; a human review takes as long as it
takes. In Claude Code, use a `/loop` with a several-minute interval or a
scheduled wake-up; a tight `sleep` loop in one shell command burns the session
and cannot be interrupted.

Stop watching when the PR is merged or closed, when changes are requested (you
now have work to do), or when the user says so.

`scripts/poll-pr-review.sh <pr-number> [owner/repo]` is the preferred wakeup
check. In one pass it lists unresolved review threads (via GraphQL, paginated
up to 2000 threads, then errors loudly instead of looping forever), every
suppressed/"previously missed" finding across *all* reviews' body text,
deduplicated (these never get a thread or comment id — see
[copilot-reviews.md](copilot-reviews.md)), and the chronologically-latest
verdict line.

Rules the script encodes:

- **Sort reviews by `sort_by(.submitted_at)` before taking the last one.**
  `.reviews[-1]` is array order, not chronological — a later review can sort
  earlier in the raw array. Field name: REST `gh api` uses snake_case
  (`submitted_at`); `gh pr view --json reviews` gives camelCase
  (`submittedAt`). Copying one selector onto the other API sorts on a
  nonexistent field with no error, just a wrong order.
- **Scan every review's body for suppressed findings, not just the
  latest.** A body-only finding in an earlier review is never resurfaced by
  a "read the latest review" poll once a later review buries it.

Without the script (a different machine, or before it's installed), the
manual equivalent is
`gh pr view <number> --json reviews -q '.reviews | sort_by(.submittedAt) | .[-1].body'`
for the verdict — **always `sort_by(.submittedAt)` first**, per the above —
plus reading every review's raw body for `**file:line**` / `* ...` bullets
under a "Suppressed comments" heading, since those never appear via
`gh api .../comments` however the query is filtered. Neither the script's
suppressed-findings list nor a manual body read replaces the thread list
below: the summary body carries no `isResolved`, thread ids, or comment ids
for the *threaded* comments, so triaging from it alone without the GraphQL
query is how a fix gets made without its thread ever being replied to.

## Reading the threads

REST comments carry no resolution state, so use GraphQL:

```
gh api graphql -f query='
query($owner:String!,$repo:String!,$pr:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$pr){
      reviewDecision
      reviewThreads(first:100){
        nodes{
          id isResolved isOutdated path line
          comments(first:20){nodes{databaseId author{login} body}}}}}}}' \
  -F owner=<owner> -F repo=<repo> -F pr=<number>
```

`nodes[].id` is the **thread** id needed to resolve. `comments.nodes[].databaseId`
is the numeric **comment** id needed to reply. They are not interchangeable.

Filter to `isResolved == false`. `isOutdated == true` means the anchored code
has since changed; still answer it, but check whether the point is already
fixed.

## Triage against the current branch

Each comment is a claim, not an instruction. Verify it technically first;
agreeing with a wrong suggestion because a reviewer made it is a failure mode.
See `superpowers:receiving-code-review`.

The branch has usually moved since the comment was written, so read the
current file and surrounding code before deciding anything. Then sort each
thread into one of five:

- **Already addressed**. A later commit fixed it. Reply with the commit sha and
  resolve.
- **Real defect**. Fix it, one atomic commit per finding.
- **Correct but out of scope**. Say so; do not widen the PR. Ask the user how
  to carry it: an issue, a follow-up PR, a backlog note, or nothing. Do not
  open an issue on your own initiative.
- **Wrong or based on a misreading**. Say why, citing the line. Do not silently
  comply and do not silently ignore.
- **Needs a decision from the user**. A genuine design choice, not a defect.
  Surface it and stop; do not guess on their behalf.

## Reporting back

Whatever gets posted, tell the user what happened, one entry per thread:

| | |
|---|---|
| **Comment** | reviewer, `file_path:line`, one line on what they said |
| **Verdict** | Already addressed / Fixed / Out of scope / Rejected / Needs your decision |
| **Detail** | what changed, with `file_path:line`, or why the comment does not hold |

Close with the counts and anything still waiting on them.

## Replying

For a whole wave of threads, `scripts/reply-threads.sh` replies to (and
optionally resolves) all of them in one GraphQL call, keyed by the
**thread** id `poll-pr-review.sh` already prints — no separate comment-id
lookup, and no REST reply-per-comment calls each silently creating their
own empty review. Feed it `thread_id<TAB>yes|no<TAB>body` lines, one per
thread, `yes`/`no` meaning resolve or not.

For a single reply, or without the script:

```
gh api -X POST repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies \
  -f body="Fixed in <sha>: ..."
gh pr comment <number> --body "..."     # only for PR-wide replies
```

Keep it to what changed and why, or why it did not. One reply per thread.

Replies go onto a public PR under the user's name, and a rejection lands in
front of the reviewer you disagree with, so apply the `writing` skill. No
"great catch", no "you're absolutely right", no apology padding around a
rejection. State what the code does, cite the line, let that carry it.

Where the verdict is **Needs a decision from the user**, draft the reply but do
not post it. That thread is theirs to answer.

## Fixing and pushing

- One commit per finding, per the atomic-commit mandate in the parent skill.
- Never force-push a branch under review without confirming; it detaches
  outdated comments and destroys the reviewer's place.
- Reference the fixing commit sha in the reply so the reviewer can jump to it.
- The commit is not the last step. Before anything else — the next wave, a
  different task, ending the turn — reply to every thread the commit
  addressed, and resolve each one that's settled (fixed and reply posted;
  not one still disputed). Pushing a fix without the matching reply queued in
  the same unit of work is the anti-pattern this skill exists to prevent.

## Resolving threads

`reply-threads.sh`'s `yes` column resolves as part of the same call. Only
GraphQL can resolve at all; without the script:

```
gh api graphql -f query='
mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){
  thread{ id isResolved }}}' -F id=<thread_id>
```

`unresolveReviewThread` is the inverse.

Resolve only when the point is settled: the fix is pushed, or the reviewer
agreed with your answer. Never resolve to clear the board; a
resolved-but-unanswered thread hides work the reviewer asked for. Threads you
disagreed with stay open until the reviewer closes them.

## Re-requesting review

After pushing fixes, ask for another pass explicitly:

```
gh pr edit <number> --add-reviewer <login>
```

Then re-check `gh pr checks <number>` before asking anyone to merge; a red
check you believe is unrelated must still be named, not ignored.

## Bot reviewers

Automated reviewers (CodeRabbit, Copilot, linters) post the same thread
structure and get the same triage, but their findings are unverified by
definition. A bot nit that does not survive verification gets a one-line
reply saying so, not a change.

Copilot in particular buries some findings as body-only prose with no thread
or comment id — see [copilot-reviews.md](copilot-reviews.md) before triaging
a Copilot review.

Before posting a reply, re-read the target comment's body and confirm it
matches what you're replying to. A comment id picked from the wrong list
entry posts the right reply under the wrong thread; if that happens, post a
correction in the same (wrong) thread pointing at the right one.
