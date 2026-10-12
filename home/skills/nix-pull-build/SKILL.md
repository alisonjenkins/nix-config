---
name: nix-pull-build
description: >-
  Pull the latest nix-config main, preserve local edits, detect and build this
  system's profile without switching, fix build errors and retry until it
  succeeds, and send a desktop notification on macOS or Linux. Use when asked
  to update and build this system's Nix configuration or invoke /nix-pull-build.
---

# Pull and build this system

Run `nix-pull-build` with no arguments. The Nix-managed command is bound to the
configured checkout, so it works regardless of the session's working directory.
It detects the actual hostname, fast-forwards main from origin/main, restores
staged, unstaged and untracked local edits, and builds the system profile into
the checkout's `result` symlink. macOS builds the hostname's Darwin configuration;
Linux builds its NixOS configuration, or a standalone Home Manager configuration
named `user@hostname`, `hostname`, or `user` (in that order) if no NixOS
configuration exists. It uses `osascript` on macOS and `notify-send` on Linux
for success and failure notifications.

Never switch, activate, use sudo, decrypt secrets, commit local workarounds,
force a pull, or discard local changes as part of this skill.

Wait for the command to finish before reporting success. If it is backgrounded,
leave its notification handling to the script and wait for completion.

If it fails, report the failing phase and preserve recovery data. A stash
conflict retains the stash and stops before building; do not drop it or resolve
conflicts without the user's direction. An existing lock may mean another run
is active; do not remove it without checking.

## Fix build errors and retry

A build failure is not the end of the task. Read the actual error and failing
derivation's logs, use the debugging and programming skills, and fix the root
cause in the configured checkout. Preserve pre-existing edits and make only
changes needed for this system's build. Do not hide errors by disabling
features, removing packages or weakening security without the user's approval.
Stage any newly added files needed by the Git-backed flake, without committing
or staging unrelated user changes.

After each fix, run relevant targeted checks, then rerun `nix-pull-build`.
The command preserves these edits across its pull and sends the final success
notification when the build completes. Continue diagnosing, fixing and
retrying until this system's complete profile builds successfully; a targeted
check or an old `result` symlink is not proof of completion.

Do not repeat an unchanged failing command indefinitely. If successive attempts
make no progress, use the consulting skill. If blocked by unavailable secrets,
credentials, permissions, infrastructure or a decision requiring user approval,
report the concrete blocker and request the necessary input rather than bypassing
it or claiming success. Pull, stash, lock and notification failures are not
build errors: address the failing phase, and do not modify the system profile
to work around them.

## Submit build fixes for review

When repairs are needed, aim to deliver them in a pull request, not leave them
as permanent local workarounds. After the full profile builds, use the git skill
to isolate only the repairs on a dedicated branch or worktree, preserving all
pre-existing user edits. Keep the configured main checkout on main so future
`nix-pull-build` runs still work.

Summarize the root cause, proposed fixes and validation, then request approval
to commit, push and open a PR unless the user has already authorized those
actions. After approval, commit only the repairs, push the branch, open the PR
and return its URL. Do not merge or activate the fixes automatically. If PR
submission is blocked, report what remains and preserve the fixes for review.

If the command is unavailable, explain that the Nix configuration must first
be built and manually switched to install it. Do not fall back to a broadly
approved shell script.
