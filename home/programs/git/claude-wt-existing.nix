{ pkgs, ... }:
let
  claude-code = if pkgs.stdenv.hostPlatform.isAarch64 then pkgs.master.claude-code else pkgs.unstable.claude-code-bin;
in
pkgs.writeShellScriptBin "claude-wt-existing" ''
  BRANCH_NAME="$1"

  if [ -z "$BRANCH_NAME" ]; then
    echo "Usage: claude-wt-existing <branch-name>"
    exit 1
  fi

  WORKTREE_PATH=".claude/worktrees/$BRANCH_NAME"

  if [ -d "$WORKTREE_PATH" ]; then
    cd "$WORKTREE_PATH" && exec ${claude-code}/bin/claude
  else
    echo "Worktree doesn't exist. Use claude-wt to create it."
    exit 1
  fi
''
