gpgSign: ''
  [branch]
    autosetuprebase = always

  [branch "master"]
    remote = origin
    merge = refs/heads/master

  [credential]
    helper = !aws codecommit credential-helper $@
    UseHttpPath = true

  [commit]
    # template = ~/.config/git/template
    gpgSign = ${
    if gpgSign
    then "true"
    else "false"
  }

  [difftool]
    prompt = false

  [filter "lfs"]
    clean = git-lfs clean -- %f
    smudge = git-lfs smudge -- %f
    process = git-lfs filter-process
    required = true

  [http]
    postBuffer = 524288000

  [mergetool]
    prompt = true

  [mergetool "nvim"]
    cmd = nvim -f -c \"Gdiffsplit!\" \"$MERGED\"

  [mergetool "nvimdiff"]
    cmd = nvim -d $BASE $LOCAL $REMOTE $MERGED -c '$wincmd w' -c 'wincmd J'

  [merge]
    tool = nvim

  [pull]
    rebase = true

  [push]
    default = current

  [rerere]
    enabled = true

  [tag]
    gpgSign = ${
    if gpgSign
    then "true"
    else "false"
  }

  [url "git@github.com:"]
    insteadof = github:

  [url "https://github.com/"]
    insteadof = githubh:

  [url "git@bitbucket.org:"]
  insteadOf = https://bitbucket.org/
''
