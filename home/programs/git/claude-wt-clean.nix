{ pkgs, ... }: pkgs.writeShellScriptBin "claude-wt-clean" ''
  BRANCH_NAME="$1"

  if [ -z "$BRANCH_NAME" ]; then
    echo "Usage: claude-wt-clean <branch-name>"
    exit 1
  fi

  WORKTREE_PATH=".claude/worktrees/$BRANCH_NAME"
  ${pkgs.git}/bin/git worktree remove "$WORKTREE_PATH"
  ${pkgs.git}/bin/git worktree prune
''
