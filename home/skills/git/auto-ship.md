# Shipping a change unattended: commit → branch → PR → review loop → auto-merge

End-to-end automation for "commit this, open a PR, get it reviewed, and merge
it once it's clean" without asking at each step. This still obeys every rule
in the parent skill — atomic commits, never squash, rebase-merge preferred —
it just chains them without pausing between stages. Ask the user before
starting only if it is unclear whether they want this to run unattended; once
started, do not stop for a status update, only for something a human must
decide.

## 1. Commit atomically

Follow [commit-messages.md](commit-messages.md): split by intent, one commit
per granular change, confirm the tree builds before each commit.

## 2. Branch

If already on a feature branch, use it. If on the default branch, create one
named `<type>/<short-desc>` from the primary commit's Conventional Commits
`type` and a 2-4 word kebab-case description of its subject, e.g.
`fix/scarlett-usb-timer-scheduling`. When the commits span more than one
`type`, use the type of the change the PR is actually about, not the first
commit chronologically.

## 3. Open the PR

Follow [pr-workflow.md](pr-workflow.md) step 1-4. Push, `gh pr create`.

## 4. Poll for review

Follow the "Watching for a review" section of
[pr-review-responses.md](pr-review-responses.md): poll on the order of
minutes via `/loop` or a scheduled wake-up, not a tight sleep loop. Each
cycle, pull both the thread list and check status:

```
gh pr checks <number>
gh api graphql -f query='
query($owner:String!,$repo:String!,$pr:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$pr){
      headRefOid
      reviewDecision
      reviewRequests(first:50){nodes{requestedReviewer{
        ... on User{login} ... on Bot{login}}}}
      reviews(last:50){nodes{author{login} state submittedAt commit{oid}}}
      reviewThreads(first:100){pageInfo{hasNextPage endCursor} nodes{id isResolved isOutdated path line
        comments(first:20){nodes{databaseId author{login} body}}}}}}}' \
  -F owner=<owner> -F repo=<repo> -F pr=<number>
```

If `pageInfo.hasNextPage` is true, page through with `reviewThreads(first:100,
after:$cursor)` before trusting the thread list for anything — most PRs never
hit 100 threads, but the merge gate below reads this list, and a truncated
page could hide unresolved threads past the first 100 and merge prematurely.

## 5. Triage and fix

For every unresolved thread, follow "Triage against the current branch",
"Replying" and "Resolving threads" in
[pr-review-responses.md](pr-review-responses.md): sort each thread into one
of the five triage outcomes, fix real defects (one atomic commit per finding,
pushed), and reply citing what changed or why it doesn't hold. Resolve only
the outcomes that settle the point — already addressed, fixed, out of scope
with the user's call on how it's carried. A thread you rejected as wrong
stays **open**, replied but unresolved, until the reviewer closes it; do not
resolve it yourself just to clear the board. Push fixes as a normal
`git push`; force-push only with the confirmation the parent skill requires.

Stop and surface to the user, do not guess: any thread sorted as "Needs a
decision from the user" in the triage table, or a check failure that looks
unrelated to this change.

## 6. Copilot re-review

Whether GitHub Copilot's PR review bot auto-reruns after you push fixes is
not reliable — it depends on the repo's `copilot_code_review` ruleset
(`review_on_push`), but has been observed to re-review on push even with
that flag set to `false`. Don't assume either way; check before requesting,
since requesting again while it's still mid-review is a no-op that just
wastes a cycle. Each poll cycle, after pushing fixes:

1. Find Copilot's login from the `reviews` *and* `reviewRequests` you already
   fetched — filter for a login containing `copilot` in either list (bot
   logins vary by installation; don't hardcode one). Checking `reviews` alone
   misses the case where Copilot has been requested but hasn't submitted its
   first review yet. Skip this section if no such reviewer exists in either
   list.
2. Check whether a re-review is already outstanding: if that login appears in
   `reviewRequests`, one is pending — wait for the next poll instead of
   requesting again.
3. Otherwise compare Copilot's most recent review's commit against
   `headRefOid` — `reviews(last:50)` returns oldest-first, so take the
   *last* entry from Copilot in the list, not the first. If they match, Copilot has already reviewed the current
   head — nothing to do. If Copilot's latest review predates the current
   head (you've pushed since), request another pass:
   ```
   gh pr edit <number> --add-reviewer <copilot-login>
   ```
   This call has been observed to return success while leaving
   `requested_reviewers` empty even when a request was genuinely needed —
   treat it as best-effort, not confirmation. Re-check on the next poll
   cycle rather than assuming the request landed.

## 7. Merge gate

All of these, not just checks green:

- Every review thread is either `isResolved: true`, or open only because it
  was rejected in step 5 and is waiting on the reviewer, not on you.
- No thread left in "Needs a decision from the user" state.
- `reviewDecision` is not `CHANGES_REQUESTED` (bots that only leave comments
  without a formal review don't set this — thread resolution is the real
  signal for them).
- `gh pr checks <number>` all passing, or a named, explained exception the
  user already accepted.

Once satisfied, enable auto-merge rather than merging immediately — GitHub
merges it the moment any still-pending required check finishes:

```
gh pr merge <number> --auto --rebase
```

Fall back to `--auto --merge` if rebase merges are disabled on the repo.
Never `--squash` (parent skill mandate). If auto-merge is not enabled on the
repo (`gh pr merge --auto` errors), merge directly once checks are already
green instead.

## Stopping conditions

Stop the loop and hand back to the user on: a thread needing their decision,
an unrelated red check, a force-push that would be needed, merge conflicts
`gh pr create`/`gh pr merge` can't resolve on their own, or being asked to
stop.
