#!/usr/bin/env bash
set -euo pipefail

: "${repository:?repository must be supplied by the Nix wrapper}"

if [[ $# -ne 0 ]]; then
  echo "nix-pull-build takes no arguments; its repository is configured in Nix." >&2
  exit 1
fi
platform="$(uname -s)"
case "$platform" in
  Darwin|Linux) ;;
  *) echo "Unsupported operating system: $platform" >&2; exit 1 ;;
esac

host="$(hostname)"
user="$(id -un)"
phase="checking repository"
stash_oid=""
restore_attempted=false
locked=false

notify() {
  if [[ "$platform" = Linux ]]; then
    notify-send -- "$1" "$2"
    return
  fi
  osascript - "$1" "$2" <<'APPLESCRIPT'
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
}

restore_edits() {
  restore_attempted=true
  echo "Restoring local edits from $stash_oid." >&2
  if ! git stash apply --index "$stash_oid"; then
    echo "Local edits remain saved in stash $stash_oid; resolve the conflict before building." >&2
    return 1
  fi
  local ref oid
  while read -r ref oid; do
    if [[ "$oid" = "$stash_oid" ]]; then
      if ! git stash drop "$ref"; then
        echo "Edits restored, but could not remove temporary stash $ref ($stash_oid)." >&2
        return 1
      fi
      stash_oid=""
      return 0
    fi
  done < <(git stash list --format='%gd %H')
  echo "Edits restored, but stash $stash_oid was not found in the stash list." >&2
  return 1
}

finish() {
  local status=$?
  trap - EXIT
  if [[ -n "$stash_oid" && "$restore_attempted" = false ]]; then
    if ! restore_edits; then status=1; fi
  fi
  if [[ "$locked" = true ]]; then
    if ! rmdir "$lock"; then
      echo "Could not release build lock: $lock" >&2
      status=1
    fi
  fi
  if [[ "$status" -eq 0 ]]; then
    if ! notify "Nix build succeeded" "$host ($revision) is ready to switch."; then
      echo "Build succeeded, but the notification failed." >&2
      status=1
    fi
  else
    echo "nix-pull-build failed while $phase (exit $status)." >&2
    if ! notify "Nix build failed" "$host: failed while $phase. Check the terminal."; then
      echo "The failure notification could not be delivered." >&2
    fi
  fi
  exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$repository"
repository="$(pwd -P)"
[[ "$(git rev-parse --show-toplevel)" = "$(pwd -P)" && -f flake.nix ]] || {
  echo "Configured path must be a Git repository root containing flake.nix: $repository" >&2
  exit 1
}
[[ "$(git symbolic-ref --short HEAD)" = main ]] || {
  echo "Refusing to update anything except the main branch." >&2
  exit 1
}
[[ "$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')" = origin/main ]] || {
  echo "main must track origin/main." >&2
  exit 1
}
lock="$(git rev-parse --git-path nix-pull-build.lock)"
if ! mkdir "$lock"; then
  echo "Another build may be running; lock exists at $lock. Do not remove an active lock." >&2
  exit 1
fi
locked=true

phase="fetching origin"
git fetch --quiet origin
git merge-base --is-ancestor HEAD origin/main || {
  echo "Local main is ahead of or diverged from origin/main; refusing to change it." >&2
  exit 1
}

phase="saving local edits"
if [[ -n "$(git status --porcelain)" ]]; then
  git stash push --include-untracked -m "nix-pull-build local edits"
  stash_oid="$(git rev-parse refs/stash)"
fi

phase="pulling latest main"
git merge --ff-only origin/main
phase="restoring local edits"
if [[ -n "$stash_oid" ]]; then restore_edits; fi

revision="$(git rev-parse --short HEAD)"
phase="selecting the profile for $host"
build_options=()
if [[ "$platform" = Darwin ]]; then
  target="darwinConfigurations.$host.system"
  build_options=(--option sandbox false)
else
  # shellcheck disable=SC2016
  target="$(NIX_PULL_BUILD_REPOSITORY="$repository" NIX_PULL_BUILD_HOST="$host" \
    NIX_PULL_BUILD_USER="$user" nix eval --impure --json --expr '
    let
      flake = builtins.getFlake (builtins.getEnv "NIX_PULL_BUILD_REPOSITORY");
      host = builtins.getEnv "NIX_PULL_BUILD_HOST";
      user = builtins.getEnv "NIX_PULL_BUILD_USER";
    in
    if builtins.hasAttr host (flake.nixosConfigurations or {}) then
      "nixosConfigurations.${builtins.toJSON host}.config.system.build.toplevel"
    else
      let
        homes = flake.homeConfigurations or {};
        candidates = [ "${user}@${host}" host user ];
        matches = builtins.filter (name: builtins.hasAttr name homes) candidates;
      in
        if matches == [] then
          throw "No NixOS or Home Manager profile found for ${user}@${host}"
        else
          "homeConfigurations.${builtins.toJSON (builtins.head matches)}.activationPackage"
  ' | jq -er .)"
fi
phase="building $host"
echo "Building $target at $revision without activating." >&2
if [[ -t 2 ]]; then
  nix build "${build_options[@]}" --out-link result "$repository#$target"
else
  # Without a TTY nix prints no progress; keep a copy that outlives a background task.
  log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/nix-pull-build"
  mkdir -p "$log_dir"
  log="$log_dir/$host.log"
  echo "Build log (live): $log" >&2
  nix build --print-build-logs "${build_options[@]}" --out-link result "$repository#$target" 2>&1 | tee "$log" >&2
fi
readlink result
