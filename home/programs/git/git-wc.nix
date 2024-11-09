{ pkgs, ... }: pkgs.writeShellScriptBin "git-wc" ''
  REPOSITORY="$1"
  REPO_NAME="$(basename $REPOSITORY)"
  REPO_NAME_NO_GIT="$(echo $REPO_NAME | sed 's/\.git$//g')"

  ${pkgs.coreutils}/bin/mkdir -p $REPO_NAME_NO_GIT/
  cd $REPO_NAME_NO_GIT
  ${pkgs.git}/bin/git clone --bare $REPOSITORY ".$REPO_NAME"

  cd ".$REPO_NAME"
  BRANCHES=($(git branch --format "%(refname:short)"))

  for BRANCH in "''${BRANCHES[@]}"; do
    ${pkgs.git}/bin/git worktree add "../$BRANCH" "$BRANCH"
  done
''
