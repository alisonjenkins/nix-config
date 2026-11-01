# Pull and build this system

`/nix-pull-build` is a shared skill for Claude Code and Copilot CLI. In Copilot,
mention it in a prompt, for example `Use /nix-pull-build`. The existing skill
discovery installs `home/skills/nix-pull-build/` into both assistants' personal
skill directories.

The skill runs the Nix-managed `nix-pull-build` command without arguments. It is
enabled by default wherever the shared programs module is imported, and can also
be run directly from a terminal.

It finds the checkout at run time, first match wins:

1. The main worktree of the Git repository containing the working directory,
   if it holds `flake.nix` and its `origin` matches
   `programs.nix-pull-build.origin` (scheme and a `.git` suffix are ignored). A
   PR worktree therefore resolves to the main checkout, which stays on `main`.
2. `programs.nix-pull-build.repository`, if set. Otherwise it fails with a
   message naming the expected origin.

The origin check is the trust boundary: the command is pre-approved, so a
`flake.nix` in some other clone must not be enough to make it fetch and build
that clone. There is no environment-variable override for the same reason.

It then:

1. Detects the operating system, hostname and current user, and requires the configured checkout's main branch to
   track origin/main, with no local-only commits.
2. Fetches origin and fast-forwards main, temporarily stashing local edits.
3. Restores staged, unstaged and untracked files before building. Ignored files
   are not stashed; pre-existing stashes are left alone.
4. Builds the matching profile into `result`, without activation or sudo,
   then sends a success or failure notification with `osascript` on macOS or
   `notify-send` on Linux. In a terminal, nix's own progress display is
   used. When stderr is not a terminal (a background task, a pipe), the build
   runs with `--print-build-logs` and its combined output goes to stderr and to
   `${XDG_STATE_HOME:-~/.local/state}/nix-pull-build/<hostname>.log`
   (truncated each run); the path is printed before the build starts, and the
   copy can be watched with `tail -f` after the task ends.

macOS selects `darwinConfigurations.<hostname>.system`. Linux selects
`nixosConfigurations.<hostname>.config.system.build.toplevel` if it exists;
otherwise it selects a standalone `homeConfigurations.<name>.activationPackage`,
looking for `user@hostname`, `hostname`, then `user`. Missing profiles fail
explicitly rather than building another host. Only macOS disables the Nix
sandbox, matching the existing Darwin build recipe.

A per-checkout lock rejects overlapping invocations. Failed updates restore
local edits where possible; stash conflicts retain the stash and stop before
building. The terminal includes the stash ID for recovery. Notifications need
a working desktop notification service/session on Linux, or permission for the
terminal application to send notifications on macOS. A notification delivery
failure is reported explicitly.

## Build error recovery

When used through the skill, the assistant diagnoses build errors, makes
targeted fixes in the configured checkout, and reruns the command until the
complete profile builds successfully. Local fixes are preserved across retries;
new files needed by the flake are staged but not committed automatically.
Running the command directly performs one attempt, not an automatic repair loop.

The skill does not permit silently disabling features, weakening security,
discarding edits or accessing secrets to make a build pass. If progress stops
or required credentials, permissions or user decisions are unavailable, the
assistant reports the blocker rather than retrying indefinitely. Stash conflicts
still require user direction; notification failures are reported separately
from build failures.

Successful repairs should become a PR: the assistant isolates the fixes from
pre-existing user edits, summarizes their cause and validation, and requests
commit/push/PR approval unless already granted. It leaves the configured main
checkout on main, returns the PR URL and never merges or activates automatically.

## Nix configuration and permissions

```nix
programs.nix-pull-build = {
  enable = true;
  repository = "${config.home.homeDirectory}/git/personal/nix-config";
};
```

`repository` is optional (default `null`) and only the fallback in step 2. The
module installs the command and adds a Claude `Bash(nix-pull-build)` approval.
When `repository` is set it also adds a repository-scoped Copilot
`commandPatterns` approval, which needs a path known at build time. No new
broad Git, shell, notification or activation approval is added. The command
rejects arguments, and only builds a checkout of `origin` or the configured
fallback, so the approval cannot select another repository, hostname or
operation. Existing broader permissions are not changed.

Build the configuration, manually switch it, and start a new assistant session
to pick up the installed command and approvals. Copilot can reload the skill
with `/skills reload`; Claude exposes `/nix-pull-build` as a skill command.

This workflow supports macOS and Linux. Set `enable = false` to opt out.
It never decrypts or displays secrets, but the Nix build still needs whatever
encrypted input files the host configuration references.

## Development

Run `bash home/programs/nix-pull-build/tests.sh` with Nix and jq on `PATH`.
The integration tests use real local Git repositories and Nix evaluation for
profile selection. They fake the system build, hostname, user, platform and
notification boundaries, plus injected Git merge and stash cleanup failures.
Both platforms' notifications and all Linux profile-selection priorities are
exercised.
The pre-commit hook runs these tests when the command changes.
