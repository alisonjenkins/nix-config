#!/usr/bin/env bash
# Summarizes outstanding GitHub PR review feedback in one pass, so polling
# doesn't rely on "check the latest review" (array order isn't chronological,
# and reviewers like Copilot often bury real findings as body-only prose —
# no comment id, no thread — in earlier reviews that a "just the latest one"
# check would never revisit). Reports two independent things:
#   - unresolved review-thread comments (GraphQL, has ids, repliable)
#   - suppressed/"previously missed" findings mentioned in ANY review's body
#     text, deduplicated — these have no thread or comment id at all
set -euo pipefail

usage() {
  echo "usage: $0 <pr-number> [owner/repo]" >&2
  echo "  owner/repo defaults to the current repo (gh repo view)" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

pr_number="$1"
if [[ -n "${2:-}" ]]; then
  owner="${2%%/*}"
  repo="${2##*/}"
else
  owner="$(gh repo view --json owner -q .owner.login)"
  repo="$(gh repo view --json name -q .name)"
fi

if ! [[ "$pr_number" =~ ^[0-9]+$ ]]; then
  echo "error: <pr-number> must be numeric, got '$pr_number'" >&2
  exit 1
fi

echo "== PR #$pr_number ($owner/$repo) =="
echo

# --- Unresolved review-thread comments: the authoritative, repliable set ---
echo "-- Unresolved review threads (repliable) --"
thread_count=0
# shellcheck disable=SC2016 # single-quoted on purpose: $owner/$repo/$pr below are GraphQL variables, not shell ones
while IFS=$'\t' read -r thread_id is_outdated path line comment_id author body; do
  [[ -z "$thread_id" ]] && continue
  thread_count=$((thread_count + 1))
  outdated_note=""
  [[ "$is_outdated" == "true" ]] && outdated_note=" [outdated: code has changed since]"
  echo "[$comment_id] $path:$line (thread $thread_id)$outdated_note"
  echo "  $author: $(head -c 300 <<<"$body" | tr '\n' ' ')"
done < <(gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$pr){
        reviewThreads(first:100){
          nodes{
            id isResolved isOutdated path line
            comments(first:1){nodes{databaseId author{login} body}}}}}}}' \
  -F owner="$owner" -F repo="$repo" -F pr="$pr_number" \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved == false)
    | [.id, (.isOutdated|tostring), .path, (.line|tostring),
       (.comments.nodes[0].databaseId|tostring), .comments.nodes[0].author.login,
       .comments.nodes[0].body] | @tsv')

if [[ $thread_count -eq 0 ]]; then
  echo "(none)"
fi
echo

# --- Suppressed / "previously missed" findings: body-only prose, no thread ---
# Copilot's review body wraps these as "**path:line**" headers followed by
# "* finding text" bullets inside a collapsed "Suppressed comments" section.
# They never get a comment id, so gh api .../comments will never show them —
# reading every review's raw body is the only way to see them at all.
echo "-- Suppressed/previously-missed findings across all reviews (dedup) --"
suppressed="$(gh api "repos/$owner/$repo/pulls/$pr_number/reviews" --paginate \
  --jq '.[] | select(.body != "") | .body' \
  | awk '
    /^\*\*[^*]+:[0-9]+\*\*$/ {
      loc = substr($0, 3, length($0) - 4)
      getline nextline
      if (nextline ~ /^\* /) {
        text = substr(nextline, 3)
        key = loc "\x1f" text
        if (!(key in seen)) {
          seen[key] = 1
          print loc "\t" text
        }
      }
      next
    }
  ' | sort -u)"
if [[ -z "$suppressed" ]]; then
  echo "(none)"
else
  while IFS=$'\t' read -r loc text; do
    echo "$loc"
    echo "  $text"
  done <<<"$suppressed"
fi
echo

# --- Latest review verdict (chronological, not array order) ---
echo "-- Latest review verdict --"
# shellcheck disable=SC2016 # single-quoted on purpose: $r below is a jq variable, not a shell one
gh api "repos/$owner/$repo/pulls/$pr_number/reviews" --paginate \
  --jq 'sort_by(.submitted_at) | map(select(.body != "")) | last as $r
    | if $r == null then "(no review with a summary yet)"
      else "[\($r.submitted_at)] \($r.user.login) on \($r.commit_id[0:8]): " + ($r.body | split("\n")[0])
      end'
