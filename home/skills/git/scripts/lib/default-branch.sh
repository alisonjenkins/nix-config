# shellcheck shell=bash
# Shared by rebase-onto-default.sh and merge-onto-default.sh. Source it,
# then call detect_default_branch; it echoes the branch name on stdout
# and returns 1 (nothing echoed) if it can't determine one.
detect_default_branch() {
  local ref candidate
  if ref="$(git symbolic-ref -q refs/remotes/origin/HEAD)"; then
    echo "${ref#refs/remotes/origin/}"
    return 0
  fi
  for candidate in main master trunk; do
    if git ls-remote --exit-code --heads origin "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}
