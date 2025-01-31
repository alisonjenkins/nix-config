if [[ ! -v XDG_CONFIG_HOME ]] || [ -z ${XDG_CONFIG_HOME+x} ];   ; then
  export XDG_CONFIG_HOME="$HOME/.config"
fi

# SSH agent
if uname -a | grep 'Linux' &> /dev/null; then
  if [ -z "$SSH_AUTH_SOCK" ]; then
    export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
  fi
fi

# Set aws-vault options
if [[ -x /usr/bin/kwalletd5 ]]; then
  export AWS_VAULT_BACKEND=kwallet
fi

# Set default editor
export EDITOR='nvim'

# Set the Go Path
export GOPATH="$HOME/go"
export GOBIN="$HOME/go/bin"

# McFly options
export MCFLY_FUZZY=2
export MCFLY_KEY_SCHEME=vim
export MCFLY_RESULTS=50

# Make shell history ignore duplicated commands and ignore any command
# starting with a space.
export HISTCONTROL=ignoredups:ignorespace

if [ -f ~/.secret_envvars ]; then
  source ~/.secret_envvars
fi

# On Mac have Homebrew Cask install applications to your user's Applications
# directory
if uname -a | grep 'Darwin' &> /dev/null; then
  export HOMEBREW_CASK_OPTS='--appdir=/Applications'
fi

# Setup Path variable
export PATH="$PATH:$HOME/.cargo/bin"
export PATH="$PATH:/opt/homebrew/bin"
export PATH="$PATH:$HOME/.local/bin"
export PATH="$PATH:$HOME/bin"
export PATH="$PATH:$HOME/go/bin"
export PATH="$PATH:/usr/local/sbin"
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# nnn Environment variables
export NNN_OPTS="aedF"
export NNN_BMS="D:~/Documents;d:~/Downloads;g:~/git;h:~;"
