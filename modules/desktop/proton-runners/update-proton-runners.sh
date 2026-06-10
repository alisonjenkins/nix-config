# shellcheck shell=bash
#
# Update Proton runners to the latest GitHub release before Steam launches.
#
# Reads runner definitions from the PROTON_RUNNERS environment variable: one
# "name|repo|assetRegex" record per line. Each runner is updated in parallel
# and the script blocks until all of them finish. Failures are non-fatal — the
# previously installed runner is left in place and the script still exits 0 so
# Steam launches regardless.
#
# Optional env:
#   STEAM_COMPAT_DIR  override the compatibilitytools.d install directory
#   GITHUB_TOKEN      authenticated GitHub API calls (avoids rate limits)

set -euo pipefail

if [ -z "${PROTON_RUNNERS:-}" ]; then
  echo "update-proton-runners: PROTON_RUNNERS is empty; nothing to do" >&2
  exit 0
fi

# Resolve the compatibilitytools.d directory. Prefer an explicit override, then
# the active install symlink, then the default XDG data path.
compat_dir="${STEAM_COMPAT_DIR:-}"
if [ -z "$compat_dir" ]; then
  if [ -d "$HOME/.steam/root" ]; then
    compat_dir="$HOME/.steam/root/compatibilitytools.d"
  else
    compat_dir="${XDG_DATA_HOME:-$HOME/.local/share}/Steam/compatibilitytools.d"
  fi
fi
state_dir="$compat_dir/.auto-update"
mkdir -p "$state_dir"

update_one() {
  local name="$1" repo="$2" regex="$3"
  local api="https://api.github.com/repos/$repo/releases/latest"
  local marker="$state_dir/$name.tag"
  local dirfile="$state_dir/$name.dir"

  local curl_args=(--fail --silent --show-error --location --max-time 30
                   -H "Accept: application/vnd.github+json")
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl_args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi

  local json
  if ! json="$(curl "${curl_args[@]}" "$api")"; then
    printf '[%s] WARN: release query failed; keeping installed version\n' "$name" >&2
    return 0
  fi

  local tag
  tag="$(printf '%s' "$json" | jq -r '.tag_name')"
  if [ -z "$tag" ] || [ "$tag" = "null" ]; then
    printf '[%s] WARN: could not read latest tag; skipping\n' "$name" >&2
    return 0
  fi

  # Already up to date and the installed directory still exists -> nothing to do.
  if [ -f "$marker" ] && [ "$(cat "$marker")" = "$tag" ] \
     && [ -f "$dirfile" ] && [ -d "$compat_dir/$(cat "$dirfile")" ]; then
    printf '[%s] up to date (%s)\n' "$name" "$tag"
    return 0
  fi

  local url
  url="$(printf '%s' "$json" \
        | jq -r --arg re "$regex" \
            '.assets[] | select(.name | test($re)) | .browser_download_url' \
        | head -n1)"
  if [ -z "$url" ] || [ "$url" = "null" ]; then
    printf '[%s] WARN: no asset matched /%s/ in %s; skipping\n' "$name" "$regex" "$tag" >&2
    return 0
  fi

  printf '[%s] updating to %s\n' "$name" "$tag"

  local tmp
  tmp="$(mktemp -d)"
  # update_one runs in a backgrounded subshell (see the dispatch loop below), so
  # an EXIT trap fires on that subshell's exit and cleans up the temp dir even if
  # `set -e` aborts the function mid-way — more robust than a RETURN trap, which
  # an unexpected error can bypass.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  if ! curl --fail --location --no-progress-meter --max-time 1800 -o "$tmp/archive" "$url"; then
    printf '[%s] WARN: download failed; keeping installed version\n' "$name" >&2
    return 0
  fi

  # Reject archives carrying absolute paths or `..` traversal before extracting —
  # a compromised release could otherwise write outside the temp dir.
  local listing
  if ! listing="$(tar -taf "$tmp/archive")"; then
    printf '[%s] WARN: could not list archive; skipping\n' "$name" >&2
    return 0
  fi
  if grep -qE '(^/|(^|/)\.\.(/|$))' <<<"$listing"; then
    printf '[%s] WARN: archive contains unsafe paths; skipping\n' "$name" >&2
    return 0
  fi

  mkdir -p "$tmp/extract"
  if ! tar -xaf "$tmp/archive" --no-absolute-names -C "$tmp/extract"; then
    printf '[%s] WARN: extraction failed; keeping installed version\n' "$name" >&2
    return 0
  fi

  # The runner tarballs contain a single top-level directory; that becomes the
  # compat tool directory Steam lists. Pick it with a glob (no pipe, so no
  # SIGPIPE interaction with `pipefail`).
  local entries=("$tmp/extract"/*)
  local top
  top="$(basename "${entries[0]}")"
  if [ "${#entries[@]}" -ne 1 ] || [ ! -d "$tmp/extract/$top" ]; then
    printf '[%s] WARN: unexpected archive layout; skipping\n' "$name" >&2
    return 0
  fi

  # Stage fully, then swap into place, so an interrupted run never leaves a
  # half-extracted compat tool that Steam would try to use.
  local staging="$compat_dir/.$top.incoming"
  rm -rf "$staging"
  mv "$tmp/extract/$top" "$staging"

  # Drop the previously installed directory for this runner if it differs. Guard
  # against a corrupted/tampered state file: only ever delete a plain directory
  # name inside compat_dir, never a path with `/` or `..` traversal.
  if [ -f "$dirfile" ]; then
    local old
    old="$(cat "$dirfile")"
    case "$old" in
      "" | "$top" | . | .. | */*) ;; # empty, unchanged, or unsafe -> skip
      *) rm -rf "${compat_dir:?}/$old" ;;
    esac
  fi

  rm -rf "${compat_dir:?}/$top"
  mv "$staging" "$compat_dir/$top"
  printf '%s' "$tag" > "$marker"
  printf '%s' "$top" > "$dirfile"
  printf '[%s] installed %s (%s)\n' "$name" "$top" "$tag"
}

pids=()
while IFS='|' read -r name repo regex; do
  [ -z "$name" ] && continue
  update_one "$name" "$repo" "$regex" &
  pids+=("$!")
done <<EOF
$PROTON_RUNNERS
EOF

for p in "${pids[@]}"; do
  wait "$p" || true
done

exit 0
