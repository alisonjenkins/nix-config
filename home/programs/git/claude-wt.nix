{ pkgs, ... }:
let
  claude-code = if pkgs.stdenv.hostPlatform.isAarch64 then pkgs.master.claude-code else pkgs.unstable.claude-code-bin;
in
pkgs.writeShellScriptBin "claude-wt" ''
  BRANCH_NAME="$1"

  if [ -z "$BRANCH_NAME" ]; then
    echo "Usage: claude-wt <branch-name>"
    exit 1
  fi

  WORKTREE_PATH=".claude/worktrees/$BRANCH_NAME"

  if [ -d "$WORKTREE_PATH" ]; then
    echo "Worktree already exists at $WORKTREE_PATH"
    cd "$WORKTREE_PATH" && exec ${claude-code}/bin/claude
  else
    ${pkgs.git}/bin/git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" && \
    cd "$WORKTREE_PATH" && exec ${claude-code}/bin/claude
  fi
''
