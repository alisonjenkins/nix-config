# Responding to review on your own PR

Covers the receiving end: watching for a review to land, answering each
thread, fixing what is real, and resolving threads. For *giving* a review, use
the `review` skill.

A fixed finding is not a closed finding. Fixing the code addresses the
defect; replying addresses the review — every wave, before moving on to
the next thing, never "fix now, reply later." Resolving is not automatic
alongside the reply: resolve only once the point is actually settled (see
"Resolving threads" below), and leave a thread you disagree with open
until the reviewer closes it. A multi-wave polling loop (bot reviewers
re-review after every push) makes the reply step easy to miss, because
nothing breaks: tests still pass, the branch still looks green. The
backlog is invisible until someone checks the PR's
Conversation tab and finds a stack of un-replied-to threads sitting
behind commits that already fixed them. If you catch yourself fixing a
second wave of findings without having replied to the first wave's
threads, stop and close out the backlog before continuing.

## Watching for a review

There is no push notification for a review; poll. Ask before starting a long
watch, and say what interval you chose.

```
gh pr view <number> --json reviewDecision,reviews,statusCheckRollup
gh pr checks <number> --watch          # checks only, blocks until they settle
```

`reviewDecision` is `APPROVED`, `CHANGES_REQUESTED`, `REVIEW_REQUIRED`, or
`null` when no review is required. It does **not** change when a reviewer
leaves unresolved line comments without submitting a verdict, so poll the
thread list too (below) rather than `reviewDecision` alone.

Poll on the order of minutes, not seconds; a human review takes as long as it
takes. In Claude Code, a `/loop` with a several-minute interval or a scheduled
wake-up is the right shape; a tight `sleep` loop in one shell command is not,
it burns the session and cannot be interrupted.

Stop watching when the PR is merged or closed, when changes are requested (you
now have work to do), or when the user says so.

`scripts/poll-pr-review.sh <pr-number> [owner/repo]` is the preferred wakeup
check: it lists every currently-unresolved review thread (via GraphQL, with
comment ids), every suppressed/"previously missed" finding mentioned across
*all* reviews' body text deduplicated (these never get a thread or comment
id — see the "Copilot's review-summary format" note under Bot reviewers
below), and the true chronologically-latest verdict line, in one pass. It
exists because a "just check `.reviews[-1]`" poll missed a real, mergeable
finding this way: `.reviews[-1]` is array order, not chronological order,
and a later review can sort earlier in the raw array (confirmed: a review
submitted after an intervening one still landed earlier in `.reviews`) — the
script always resolves the latest by `sort_by(.submitted_at)`. It also
catches suppressed-only findings that a "read the latest review" poll would
never revisit once a later review buries them, which is exactly how a real
arithmetic-validation bug shipped to `main` unfixed on this session's own
delegate-to-copilot PR: the finding existed as body-only prose in a review
that predated the merge, and nothing ever surfaced it again after that.

If the script isn't available (a different machine, or before it's
installed), the manual equivalent is
`gh pr view <number> --json reviews -q '.reviews | sort_by(.submittedAt) | .[-1].body'`
for the verdict — **always `sort_by(.submittedAt)` first**, per the above —
plus manually reading every review's raw body for `**file:line**` / `* ...`
bullets under a "Suppressed comments" heading, since those never appear via
`gh api .../comments` no matter how the query is filtered. Neither the
script's suppressed-findings list nor a manual body read is a substitute for
the thread list below: the summary body does not carry `isResolved`, thread
ids, or comment ids for the *threaded* comments, so triaging from it alone
and never touching the GraphQL query is how a fix gets made without the
thread it addresses ever being replied to.

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

Filter to `isResolved == false`. `isOutdated == true` means the code it was
anchored to has since changed; still answer it, but check whether the point
already got fixed.

## Triage against the current branch

Each comment is a claim, not an instruction. Verify it technically first;
agreeing with a wrong suggestion because a reviewer made it is a failure mode.
See `superpowers:receiving-code-review`.

The branch has usually moved since the comment was written, so read the current
state of the file and the code around it before deciding anything. Then sort
each thread into one of five:

- **Already addressed**. A later commit fixed it. Reply with the commit sha and
  resolve.
- **Real defect**. Fix it, one atomic commit per finding.
- **Correct but out of scope**. Say so and do not widen the PR. Ask the user
  how they want it carried: an issue, a follow-up PR, a note in the backlog, or
  nothing. Do not open an issue on your own initiative.
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

Reply inside the thread, not as a new top-level comment, or the reviewer
cannot follow it:

```
gh api -X POST repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies \
  -f body="Fixed in <sha>: ..."
gh pr comment <number> --body "..."     # only for PR-wide replies
```

Keep it to what changed and why, or why it did not. One reply per thread.

These replies go onto a public PR under the user's name, and a rejection lands
in front of the reviewer you are disagreeing with, so apply the `writing`
skill. No "great catch", no "you're absolutely right", no apology padding
around a rejection. State what the code does, cite the line, let that carry it.

Where the verdict is **Needs a decision from the user**, draft the reply but do
not post it. That thread is theirs to answer.

## Fixing and pushing

- One commit per finding, per the atomic-commit mandate in the parent skill.
- Never force-push a branch under review without confirming; it detaches
  outdated comments and destroys the reviewer's place.
- Reference the fixing commit sha in the reply so the reviewer can jump to it.
- The commit is not the last step. Before moving on to anything else — the
  next wave, a different task, ending the turn — reply to every thread the
  commit addressed, and resolve each one that's actually settled (fixed and
  the reply posted; not one you're still disputing). If you are about to
  push a fix without the matching reply queued in the same unit of work,
  that is the anti-pattern this skill exists to prevent.

## Resolving threads

Only GraphQL can resolve:

```
gh api graphql -f query='
mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){
  thread{ id isResolved }}}' -F id=<thread_id>
```

`unresolveReviewThread` is the inverse.

Resolve a thread only when the point is actually settled: the fix is pushed,
or the reviewer agreed with your answer. Never resolve a thread to clear the
board; a resolved-but-unanswered thread hides work the reviewer asked for.
Threads where you disagreed stay open until the reviewer closes them.

## Re-requesting review

After pushing fixes, ask for another pass explicitly:

```
gh pr edit <number> --add-reviewer <login>
```

Then re-check `gh pr checks <number>` before asking anyone to merge; a red
check you believe is unrelated must still be named, not ignored.

## Bot reviewers

Automated reviewers (CodeRabbit, Copilot, linters) post the same thread
structure and are handled the same way, but their findings are unverified by
definition. Apply the same triage; a bot nit that does not survive
verification gets a one-line reply saying so, not a change.

### Copilot's review-summary format

GitHub Copilot's PR reviewer (`copilot-pull-request-reviewer`) wraps its
findings in a review body with a collapsed `<details><summary>Review
details</summary>` block, and that block mixes two different kinds of
finding that need different handling:

- **`Comments generated: N new`** — these exist as real, separate PR review
  comments with their own `id`/`databaseId`, fetchable via
  `gh api repos/{owner}/{repo}/pulls/{number}/comments` or the GraphQL query
  above. Filter to the ones this review actually generated by matching
  `pull_request_review_id == <this review's id>` and `in_reply_to_id ==
  null` — filtering by `commit_id` alone is unreliable (a comment's
  `commit_id` doesn't always match the review's own `commit_id`), and a
  reply you post yourself creates its own `pull_request_review_id`, so
  without the `in_reply_to_id == null` check a later scan can pick up your
  own replies as if they were new findings. These get the normal
  triage-and-reply treatment.
- **`Suppressed comments (N)` — `Previously missed (N)`** — these are prose
  only, embedded as `**file:line** * finding text` bullets *inside the
  review body itself*. They have **no comment id, no thread, nothing to
  fetch or reply to inline** — `gh api .../comments` will come back empty
  for them no matter how the query is filtered. `scripts/poll-pr-review.sh`
  extracts and deduplicates these across every review automatically; the
  manual equivalent is reading every review's raw body text (`gh api
  repos/{owner}/{repo}/pulls/{number}/reviews --jq '.[].body'`) since a
  single "read the latest review" check will never revisit one buried in an
  earlier review. Since there's no thread, there's nothing to resolve
  either; note the verdict in the PR description instead (still triage
  each one for real, including checking whether it's already stale —
  "previously missed" often re-surfaces a finding against an old commit
  that a later push already fixed).

When a review mixes both kinds, handle the `N new` ones as threads and the
suppressed ones as body-only prose findings — don't assume every bullet
under "Review details" has a matching `gh api` comment just because some do.

Before posting a reply, print or re-read the target comment's own body
first and confirm it actually matches what you're replying to. Batching
several findings' replies close together is exactly when a wrong comment
id gets used for the wrong reply — confirmed this session: a reply meant
for one finding landed under a different, unrelated thread because the id
was taken from the wrong entry in a list. If that happens, post a
correction in the same (wrong) thread pointing at the right one; don't
leave it uncorrected.
