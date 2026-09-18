#!/usr/bin/env bash
# Replies to (and optionally resolves) a whole wave of review threads in
# one GraphQL call, instead of the REST reply-per-comment endpoint (each
# call creates an empty review of its own -- a real PR with N replies
# ends up with N extra reviews cluttering the list) plus one
# resolveReviewThread mutation per thread on top. Takes the *thread* id
# (what poll-pr-review.sh already prints), not a comment id -- the two
# are not interchangeable, and this sidesteps that distinction entirely.
set -euo pipefail

usage() {
  echo "usage: $0 [input-file]" >&2
  echo "  reads TSV lines from the file, or stdin if omitted:" >&2
  echo "    thread_id<TAB>resolve(yes|no)<TAB>body" >&2
  echo "  body runs to end of line; embedded tabs in it are fine." >&2
}

if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi

input="${1:--}"
if [[ "$input" != "-" && ! -f "$input" ]]; then
  echo "error: input file not found: $input" >&2
  exit 1
fi

thread_ids=()
resolves=()
bodies=()

while IFS=$'\t' read -r thread_id resolve body || [[ -n "$thread_id" ]]; do
  [[ -z "$thread_id" ]] && continue
  case "$resolve" in
    yes | no) ;;
    *)
      echo "error: resolve column must be 'yes' or 'no', got '$resolve' for thread $thread_id" >&2
      exit 1
      ;;
  esac
  thread_ids+=("$thread_id")
  resolves+=("$resolve")
  bodies+=("$body")
done < <(if [[ "$input" == "-" ]]; then cat; else cat "$input"; fi)

if [[ ${#thread_ids[@]} -eq 0 ]]; then
  echo "(no threads to reply to)"
  exit 0
fi

query_parts=()
mutation_fields=()
gh_args=()

for i in "${!thread_ids[@]}"; do
  query_parts+=("\$t$i:ID!" "\$b$i:String!")
  mutation_fields+=("r$i: addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:\$t$i,body:\$b$i}){comment{id}}")
  gh_args+=(-F "t$i=${thread_ids[$i]}" -f "b$i=${bodies[$i]}")
  if [[ "${resolves[$i]}" == "yes" ]]; then
    mutation_fields+=("s$i: resolveReviewThread(input:{threadId:\$t$i}){thread{id isResolved}}")
  fi
done

query="mutation($(
  IFS=,
  echo "${query_parts[*]}"
)){$(printf '%s ' "${mutation_fields[@]}")}"

# A GraphQL response can carry a 200 status with a top-level "errors"
# array alongside partial "data" -- one aliased field failing doesn't
# fail the HTTP request, so `gh api`'s own exit code alone isn't enough;
# check for that field explicitly. A partial failure means some
# replies/resolutions in this batch landed and others didn't -- there is
# no atomicity across the aliased fields in one mutation.
response="$(gh api graphql -f query="$query" "${gh_args[@]}" 2>&1)" && call_status=0 || call_status=$?
if [[ $call_status -ne 0 ]]; then
  echo "$response" >&2
  echo "error: GraphQL reply/resolve call failed outright — nothing in this batch landed" >&2
  exit 1
fi
if jq -e 'has("errors")' <<<"$response" >/dev/null 2>&1; then
  echo "$response" >&2
  echo "error: GraphQL reported partial errors — some replies/resolutions in this batch may not have landed; check which above" >&2
  exit 1
fi

echo "replied to ${#thread_ids[@]} thread(s)"
resolved_count=0
for r in "${resolves[@]}"; do
  [[ "$r" == "yes" ]] && resolved_count=$((resolved_count + 1))
done
if [[ $resolved_count -gt 0 ]]; then
  echo "resolved $resolved_count of them"
fi
