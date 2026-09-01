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
re-review after every push) makes skipping the reply step easy to not
notice, because nothing breaks: tests still pass, the branch still looks
green. The backlog is invisible until someone checks the PR's
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

`gh pr view <number> --json reviews -q '.reviews[-1].body'` is a cheap way to
notice that a *new wave* landed — it returns the reviewer's plain-text summary
body, which is convenient for a poll loop's wakeup check. It is **not** a
substitute for the thread list below: the summary body does not carry
`isResolved`, thread ids, or comment ids, so triaging from it alone and never
touching the GraphQL query is how a fix gets made without the thread it
addresses ever being replied to. Treat a summary-body poll as a trigger to go
read the actual threads, not as the triage source itself.

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
