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
