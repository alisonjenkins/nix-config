# shellcheck shell=bash
# Shared by poll-pr-review.sh and pr-status.sh, which fetch reviews from
# different APIs (REST vs GraphQL) but parse the bodies identically. Each
# function reads review body text on stdin.

# Suppressed / "previously missed" findings: body-only prose, no thread.
# Copilot's review body wraps these as "**path:line**" headers followed by
# "* finding text" bullets inside a collapsed "Suppressed comments" section.
# They never get a comment id, so gh api .../comments will never show them;
# reading every review's raw body is the only way to see them at all.
# A bullet can wrap onto further physical lines with no leading "* "; those
# are joined into the same finding (space-separated) until a blank line, a
# new "**path:line**" header, or a new "* " bullet ends it — otherwise only
# the bullet's first physical line was kept, silently truncating the rest.
# Input: every review body, concatenated. Prints each distinct finding as
# its location then the indented text, or "(none)".
print_suppressed_findings() {
  local suppressed loc text
  suppressed="$(awk '
    function flush() {
      if (have) {
        key = loc "\x1f" text
        if (!(key in seen)) {
          seen[key] = 1
          print loc "\t" text
        }
      }
      have = 0
      text = ""
    }
    /^\*\*[^*]+:[0-9]+\*\*$/ {
      flush()
      loc = substr($0, 3, length($0) - 4)
      pending = 1
      next
    }
    pending && /^\* / {
      text = substr($0, 3)
      have = 1
      pending = 0
      next
    }
    pending {
      pending = 0
      next
    }
    have && /^[ \t]*$/ {
      flush()
      next
    }
    have && /^\* / {
      # a bare bullet with no header of its own ends the previous findings
      # continuation; it is not itself captured (same as a header-less bullet)
      flush()
      next
    }
    have {
      line = $0
      sub(/^[ \t]+/, "", line)
      text = text " " line
      next
    }
    END { flush() }
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
