{ pkgs, ... }: pkgs.writeShellScriptBin "claude-wt-list" ''
  ${pkgs.git}/bin/git worktree list
''
