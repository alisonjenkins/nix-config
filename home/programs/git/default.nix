{ gitUserName
, gitEmail
, gitGPGSigningKey ? "~/.ssh/id_personal.pub"
, pkgs
, ...
}:
let
  gpgSign = gitGPGSigningKey != "";
  gpgSigningProgram = (
    if pkgs.stdenv.isLinux then
      "${pkgs._1password-gui}/bin/op-ssh-sign"
    else if pkgs.stdenv.isDarwin then
      "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    else
      ""
  );
in
{
  programs.git =
    {
      enable = true;
      lfs.enable = true;
      userEmail = gitEmail;
      userName = gitUserName;

      aliases = {
        # branch
        b = "branch";
        bc = "checkout -b";
        bl = "branch -v";
        bC = "!git checkout main && git fetch -p && git branch --merged | grep -v -E '^\*|main|master|develop$' | xargs git branch -d";
        bL = "branch -av";
        bx = "branch -d";
        bX = "branch -D";
        bm = "branch -m";
        bM = "branch -M";
        bs = "show-branch";
        bS = "show-branch -a";
        go = "!f() { git checkout -b \"$1\" 2> /dev/null || git checkout \"$1\"; }; f";

        # checkout/fetch/merge/push/rebase
        # checkout
        co = "checkout";
        co0 = "checkout HEAD --";
        # fetch
        f = "fetch";
        fm = "pull";
        fo = "fetch origin";
        # merge
        m = "merge";
        mom = "merge origin/master";
        # push
        p = "push";
        pa = "push --all";
        pt = "push --tags";
        pfl = "push --force-with-lease";
        # rebase
        r = "rebase";
        ra = "rebase --abort";
        rc = "rebase --continue";
        ri = "rebase --interactive";
        rs = "rebase --skip";
        rom = "rebase origin/master";

        # conflict resolution
        conflicted = "!vim +Conflicted";

        # commit
        c = "commit -v";
        ca = "commit --all -v";
        cm = "commit --message";
        cam = "commit --all --message";
        camend = "commit --amend --reuse-message HEAD";
        cundo = "reset --soft \"HEAD^\"";
        cp = "cherry-pick";

        # diff
        d = "diff"; # Diff working dir to index
        ds = "diff --staged"; # Diff index to HEAD
        dc = "diff --staged"; # Diff index to HEAD
        dh = "diff HEAD"; # Diff working dir and index to HEAD
        hub = "browse";
        hubd = "compare";

        # index
        s = "status";
        a = "add";
        ia = "add";
        ir = "reset";

        # log
        l = "log --topo-order --pretty=format:'%C(yellow)%h %C(cyan)%cn %C(blue)%cr%C(reset) %s'";
        ls = "log --topo-order --stat --pretty=format:'%C(bold)%C(yellow)Commit:%C(reset) %C(yellow)%H%C(red)%d%n%C(bold)%C(yellow)Author:%C(reset) %C(cyan)%an <%ae>%n%C(bold)%C(yellow)Date:%C(reset)   %C(blue)%ai (%ar)%C(reset)%n%+B'";
        ld = "log --topo-order --stat --patch --full-diff --pretty=format:'%C(bold)%C(yellow)Commit:%C(reset) %C(yellow)%H%C(red)%d%n%C(bold)%C(yellow)Author:%C(reset) %C(cyan)%an <%ae>%n%C(bold)%C(yellow)Date:%C(reset)   %C(blue)%ai (%ar)%C(reset)%n%+B'";
        lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        lga = "log --topo-order --all --graph --pretty=format:'%C(yellow)%h %C(cyan)%cn%C(reset) %s %C(red)%d%C(reset)%n'";
        lm = "log --topo-order --pretty=format:'%s'";
        lh = "shortlog --summary --numbered";
        llf = "fsck --lost-found";

        lg1 = "log --graph --abbrev-commit --decorate --date=relative --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --all";
        lg2 = "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset)%C(bold yellow)%d%C(reset)%n''          %C(white)%s%C(reset) %C(dim white)- %an%C(reset)' --all";

        # remote
        re = "remote";
        rel = "remote --verbose";
        rea = "remote add";
        rex = "remote rm";
        rem = "remote rename";

        # Push the current branch to the remote "origin", and set it to track
        # the upstream branch
        publish = "!git push -u origin $(git branch-name)";
        # Delete the remote version of the current branch
        unpublish = "!git push origin :$(git branch-name)";

        # Git status-all - shows the status of all git repos under a directory
        # https://stackoverflow.com/questions/12499195/git-how-to-find-all-unpushed-commits-for-all-projects-in-a-directory
        status-all = "!for d in `find . -name \".git\"`; do echo \"\n*** Repository: $d ***\" && git --git-dir=$d --work-tree=$d/.. status; done";

        # Git work
        work = "!sh -c 'git fetch && git checkout @{upstream} -tb \\\"$@\\\"' _";
      };

      difftastic = {
        enable = true;
        background = "dark";
      };

      includes = [
        {
          path = "~/.config/git/includes/extra-config";
        }
      ];
    }
    // (
      if gpgSign
      then {
        signing = {
          key = gitGPGSigningKey;
          signByDefault = true;
        };
      }
      else { }
    );

  home.packages =
    let
      git-wc = import ./git-wc.nix { inherit pkgs; };
    in
    [
      git-wc
    ];

  home.file = {
    ".config/git/includes/extra-config".text = import ./extra-config.nix { inherit gpgSign gitGPGSigningKey gpgSigningProgram pkgs; };
  };
}
