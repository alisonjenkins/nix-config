# Copilot review state: pending, done, or clean

Before triaging anything, know which of three states Copilot's review is in.
Confusing "hasn't reviewed yet" with "reviewed and found nothing" is what
causes a merge to land before Copilot's feedback shows up.

- **Pending (mid-review).** Copilot's login appears in `pr-status.sh`'s
  `reviewRequests=` field. It was requested (on PR open, or by re-request
  after a push) but has not submitted a review against the current head yet.
  Copilot review is not instant — it commonly takes on the order of a few
  minutes. **Never merge while Copilot's login is in `reviewRequests=`.** This
  is a hard merge-gate condition (see step 7 of [auto-ship.md](auto-ship.md)),
  not just the re-review-request check in step 6 — a PR with zero unresolved
  threads and `reviewDecision` not `CHANGES_REQUESTED` still looks mergeable
  by every other signal if Copilot simply hasn't spoken yet.
- **Done, with feedback.** Copilot's entry in `latestReviews` has
  `commit.oid == head` (from `pr-status.sh`'s `head=`) and its login is no
  longer in `reviewRequests=`. Triage its threads and any suppressed findings
  as usual (see the format section below).
- **Done, clean ("no further feedback").** Same as above, but the review left
  zero unresolved threads for that review and zero suppressed bullets in its
  body. Copilot's own wording for a clean pass varies by installation (seen:
  "no issues found", "no further comments", or a body that's just the
  collapsed `<details>` block reading `Comments generated: 0 new`) — match on
  the *absence* of findings (thread count + suppressed-bullet count both
  zero), not on grepping for one exact phrase that could change format. This
  state satisfies the merge gate; don't hold the merge waiting for a second
  Copilot pass that was never coming.

Check pending-vs-done first, every poll cycle, before reading review bodies —
a body from a stale review (submitted before the current head) is not
"clean", it's just old.

# Copilot's review-summary format

GitHub Copilot's PR reviewer (`copilot-pull-request-reviewer`) wraps its
findings in a collapsed `<details><summary>Review details</summary>` block in
the review body. That block mixes two kinds of finding needing different
handling:

- **`Comments generated: N new`** — real, separate PR review comments with
  their own `id`/`databaseId`, fetchable via
  `gh api repos/{owner}/{repo}/pulls/{number}/comments` or the GraphQL query
  in [pr-review-responses.md](pr-review-responses.md). Filter to this
  review's own by matching `pull_request_review_id == <this review's id>`
  and `in_reply_to_id == null`. Filtering by `commit_id` alone is unreliable
  (a comment's `commit_id` doesn't always match the review's), and a reply
  you post creates its own `pull_request_review_id`, so without the
  `in_reply_to_id == null` check a later scan picks up your own replies as
  new findings. These get normal triage-and-reply treatment.
- **`Suppressed comments (N)` — `Previously missed (N)`** — prose only,
  embedded as `**file:line** * finding text` bullets *inside the review body
  itself*. **No comment id, no thread, nothing to fetch or reply to inline**;
  `gh api .../comments` returns nothing for them however the query is
  filtered. `scripts/poll-pr-review.sh` extracts and deduplicates these
  across every review; the manual equivalent is reading every review's raw
  body (`gh api repos/{owner}/{repo}/pulls/{number}/reviews --jq
  '.[].body'`), since a "read the latest review" check never revisits one
  buried in an earlier review. No thread means nothing to resolve; note the
  verdict in the PR description instead. Still triage each one for real,
  including whether it's stale — "previously missed" often re-surfaces a
  finding against an old commit that a later push already fixed.

When a review mixes both kinds, handle the `N new` ones as threads and the
suppressed ones as body-only prose; don't assume every bullet under "Review
details" has a matching `gh api` comment because some do.
