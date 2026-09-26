# shellcheck shell=bash
# Shared by poll-pr-review.sh and pr-status.sh, which fetch reviews from
# different APIs (REST vs GraphQL) but parse the bodies identically. Each
# function reads review body text on stdin.

# Suppressed / "previously missed" findings: body-only prose, no thread.
# Copilot's review body wraps these as "**path:line**" headers followed by
# "* finding text" bullets inside a collapsed "Suppressed comments" section.
# They never get a comment id, so gh api .../comments will never show them;
# reading every review's raw body is the only way to see them at all.
# Input: every review body, concatenated. Prints each distinct finding as
# its location then the indented text, or "(none)".
print_suppressed_findings() {
  local suppressed loc text
  suppressed="$(awk '
    /^\*\*[^*]+:[0-9]+\*\*$/ {
      loc = substr($0, 3, length($0) - 4)
      # getline returns 0 at EOF and -1 on error; unchecked, nextline
      # keeps its previous value, so a header at the very end of input
      # could wrongly inherit a bullet line from an earlier record.
      got = (getline nextline)
      if (got > 0 && nextline ~ /^\* /) {
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
    return
  fi
  while IFS=$'\t' read -r loc text; do
    echo "$loc"
    echo "  $text"
  done <<<"$suppressed"
}

# The body's literal first line is near-useless for bots like Copilot's
# reviewer: it's an HTML marker comment (<!-- ccr-overview-v2 -->), with
# the actual verdict ("### Needs a closer look", plus its explanation
# paragraph) several lines further down. `split("\n")[0]` alone silently
# hid every such verdict behind that comment; this skips comment/heading
# noise and stops before the trailing metadata (**Review effort**,
# <details>) instead.
# Input: one review body. Prints its verdict lines.
print_review_verdict() {
  awk '
    /^<!--/ { next }
    /^##[^#]/ { next }
    /^\*\*Review effort/ { exit }
    /^<details/ { exit }
    /^$/ { if (started) print; next }
    { started = 1; print }
  '
}
