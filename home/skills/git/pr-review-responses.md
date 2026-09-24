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

There is no push notification for a review; poll. Start the watch
automatically as soon as a PR is opened (see [pr-workflow.md](pr-workflow.md)
step 5) — no need to ask — and say what interval you chose.

```
gh pr view <number> --json reviewDecision,reviews,statusCheckRollup
gh pr checks <number> --watch          # checks only, blocks until they settle
```

`reviewDecision` is `APPROVED`, `CHANGES_REQUESTED`, `REVIEW_REQUIRED`, or
`null` when no review is required. It does **not** change when a reviewer
leaves unresolved line comments without a verdict, so poll the thread list
too (below), not `reviewDecision` alone.

**Poll without spending a model turn per tick.** In Claude Code,
`scripts/watch-pr.sh <pr-number> [owner/repo]` run via `run_in_background`
(or a Monitor) does the whole loop in bash: keeps the branch rebased onto
the default branch every tick (no model needed for a clean rebase), and
exits — waking you — only when a cheap `gh pr view` fingerprint actually
changes, a rebase conflict needs judgement, or 24h passes idle. It needs
exclusive use of its checkout for the whole run — give it its own worktree
if you'll keep working in this one in the meantime, or its next tick fails:
it rebases whatever you switched to, and a rebase refuses a tree with
uncommitted edits (`NEEDS_ATTENTION`). It treats the review state on
its first tick as the baseline; set `WATCH_PR_TRIAGED_REVIEWS=<count you
triaged>` (`gh pr view <n> --json reviews -q '.reviews|length'`) so a review
that landed after your triage wakes you instead of being swallowed. Re-triage
and pass the fresh count on every relaunch: a stale count differs from the
current one and wakes you again immediately, in a loop. A
ScheduleWakeup/`/loop` tick, by contrast, is a full model turn even when
nothing changed; reserve it for when no background-execution mechanism is
available. Either way, back off exponentially rather than a fixed interval —
start at 1 minute, ~1.5x per empty tick, capped at 15 minutes — since most of
a review's wait time is spent doing nothing (`watch-pr.sh` does this
internally; a manual loop should too). A user-specified interval overrides
the ramp and stays fixed at whatever they asked for.

**`watch-pr.sh` is single-shot, not a persistent daemon.** It detects ONE
change (or one of `NEEDS_ATTENTION`/`PR_CLOSED`/`PR_MERGED`/`IDLE_TIMEOUT`),
prints it, and exits — it does not loop back and keep watching on its own.
Launching it with `run_in_background` and moving on (`&disown` or
equivalent, no follow-up) means its exit is silently missed: nothing
surfaces the moment it fires, and any review activity after that point goes
unnoticed until something else prompts a manual `pr-status.sh` check —
observed in practice losing an entire round of Copilot feedback this way.
Either await its background-task completion notification directly (don't
detach without a plan to notice), or use a Monitor on it, and **relaunch it
again immediately** every time it exits for a reason other than
PR-closed/merged — one launch only covers one event.

If falling back to `ScheduleWakeup` (no background execution available),
pass this ramp's numbers explicitly (`delaySeconds: 60` on the first tick,
×1.5 per empty tick, capped at 900) — do not reach for that tool's generic
20-30 minute idle-tick default. Watching a PR review is "actively polling
external state the harness can't notify you about," which that tool's own
guidance says to pace from how fast the state actually changes, not the
no-signal idle case. A stale-but-open Copilot review (see "Copilot review
state" in [copilot-reviews.md](copilot-reviews.md)) is exactly the kind of
activity a 20-minute-first-tick poll misses or badly delays reacting to.

Stop watching when the PR is merged or closed, when changes are requested (you
now have work to do), **24 hours pass with no new activity** (report that and
hand back to the user rather than polling indefinitely), or when the user
says so.

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
- **Never take the verdict body's literal first line.** For a bot reviewer
  like Copilot, that line is an HTML marker comment
  (`<!-- ccr-overview-v2 -->`) — a `split("\n")[0]` extraction silently
  hides the actual verdict (e.g. `### Needs a closer look`, plus its
  explanation paragraph) several lines further down, several review cycles
  in a row, with no error and no obviously-wrong output — the script still
  prints *something*, just the wrong line. Found live: real "needs a
  closer look" feedback went unnoticed this way. Filter out `<!--`
  comments and `##` headings, keep everything from the first real content
  line up to `**Review effort**`/`<details>` (Copilot's fixed
  end-of-summary markers), same as `pr-status.sh` and `poll-pr-review.sh`
  now both do.

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
agreeing with a wrong suggestion because a reviewer made it is a failure
mode. When several threads are related, understand all of them before
implementing any — partial understanding produces a wrong fix for the
first one you touch.

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
