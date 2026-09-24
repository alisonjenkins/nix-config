# Shipping a change unattended: commit → branch → PR → review loop → auto-merge

End-to-end automation for "commit this, open a PR, get it reviewed, and merge
it once it's clean" without asking at each step. Every parent-skill rule still
applies — atomic commits, never squash, rebase-merge preferred — chained
without pausing between stages. Ask before starting only if it is unclear the
user wants this unattended; once started, stop only for something a human must
decide, never for a status update.

## 1. Commit atomically

Follow [commit-messages.md](commit-messages.md): split by intent, one commit
per granular change, confirm the tree builds before each commit.

## 2. Branch

On a feature branch already: use it. On the default branch: create
`<type>/<short-desc>` from the primary commit's Conventional Commits `type`
and a 2-4 word kebab-case subject, e.g. `fix/scarlett-usb-timer-scheduling`.
When commits span more than one `type`, use the type of the change the PR is
about, not the chronologically first commit.

## 3. Open the PR

Follow [pr-workflow.md](pr-workflow.md) step 1-5. Push, `gh pr create`,
start the watch.

## 4. Poll for review

Follow the "Watching for a review" section of
[pr-review-responses.md](pr-review-responses.md): run
`scripts/watch-pr.sh <number> [owner/repo]` via `run_in_background`/a
Monitor — it keeps the branch rebased and only wakes you on real activity, a
rebase conflict, or 24h idle, with no model turn spent per tick. When it
wakes you, `scripts/pr-status.sh <number> [owner/repo]` gives the full
picture in one call — checks, `reviewDecision`, `mergeable`/
`mergeStateStatus`, the paginated unresolved thread list, and the latest
review with a summary — instead of separately running `gh pr checks` plus a
hand-typed GraphQL query.

## 5. Triage and fix

For every unresolved thread, follow "Triage against the current branch",
"Replying" and "Resolving threads" in
[pr-review-responses.md](pr-review-responses.md): sort each thread into one
of the five triage outcomes, fix real defects (one atomic commit per finding,
pushed), and reply citing what changed or why it doesn't hold. Resolve only
outcomes that settle the point — already addressed, fixed, out of scope with
the user's call on how it's carried. A thread you rejected stays **open**,
replied but unresolved, until the reviewer closes it; never resolve it to
clear the board. Push fixes with a normal `git push`; force-push only with the
confirmation the parent skill requires.

Stop and surface to the user, don't guess: any thread sorted as "Needs a
decision from the user", or a check failure that looks unrelated to this
change.

## 6. Copilot re-review

Whether GitHub Copilot's PR review bot auto-reruns after a push is unreliable:
it depends on the repo's `copilot_code_review` ruleset (`review_on_push`), but
has been observed to re-review on push even with that flag `false`. Don't
assume either way; check before requesting, since requesting mid-review is a
no-op that wastes a cycle. Each poll cycle, after pushing fixes:

1. Find Copilot's login in `pr-status.sh`'s `reviewRequests=` line, or as a
   login containing `copilot` among `latestReviews`' authors (bot logins vary
   by installation; don't hardcode one). `latestReviews` alone misses the
   case where Copilot was requested but hasn't submitted its first review
   yet. Skip this section if no such reviewer exists in either place.
2. If that login appears in `reviewRequests=`, a re-review is already
   pending — wait for the next poll instead of requesting again.
3. Otherwise compare Copilot's entry in `latestReviews` (already the latest
   per author, no oldest-first array-order footgun to work around) against
   `head=`. If they match, Copilot has reviewed the current head — nothing
   to do. If its review predates the head (you've pushed since), request
   another pass:
   ```
   gh pr edit <number> --add-reviewer <copilot-login>
   ```
   This call has been observed to return success while leaving
   `requested_reviewers` empty even when a request was needed — treat it as
   best-effort, not confirmation. Re-check next poll cycle rather than
   assuming it landed.

## 7. Merge gate

All of these, not just checks green (`pr-status.sh` reports all of them):

- Copilot's login — the one actually identified in step 6, not a "bot
  reviewer" category `pr-status.sh` doesn't label — is not still in
  `reviewRequests=`. This is independent of `reviewDecision` and thread
  count: a freshly-requested review has neither yet, and looks clean by
  every other signal purely because it hasn't spoken. See "Copilot review
  state" in [copilot-reviews.md](copilot-reviews.md). A review that finished
  with zero findings ("done, clean") is not the same as one that hasn't
  started — the former clears this condition, the latter blocks the merge.
- Every review thread is either `isResolved: true`, or open only because it
  was rejected in step 5 and is waiting on the reviewer, not on you.
- No thread left in "Needs a decision from the user" state.
- `reviewDecision` is not `CHANGES_REQUESTED` (bots that only leave comments
  without a formal review don't set this — thread resolution is the real
  signal for them).
- `checks=` is not pending or failing, or a named, explained exception the
  user already accepted.

Once satisfied: `scripts/merge-onto-default.sh` — rebases locally, gates on
the PR's checks itself, and pushes straight to the default branch,
signatures intact (see [pr-workflow.md](pr-workflow.md)'s Merging section).
Only fall back to `gh pr merge --rebase`/`--merge` (never `--squash`) if it's
rejected because the repo requires merging via a pull request — that lands
unsigned regardless of the source commits, so ask the user first if that
matters for this repo.

## Stopping conditions

Stop the loop and hand back to the user on: a thread needing their decision,
an unrelated red check, a force-push that would be needed, a merge conflict
neither side of which is clearly superseded (see
[merge-conflicts.md](merge-conflicts.md)), or being asked to stop.
