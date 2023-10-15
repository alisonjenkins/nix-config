if [[ ! -v XDG_CONFIG_HOME ]] || [ -z ${XDG_CONFIG_HOME+x} ];   ; then
  export XDG_CONFIG_HOME="$HOME/.config"
fi

# SSH agent
if uname -a | grep 'Linux' &> /dev/null; then
  if [ -z "$SSH_AUTH_SOCK" ]; then
    export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
  fi
fi

# Set AWS Region
export AWS_DEFAULT_REGION='eu-west-2'

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
export PATH="$PATH:$HOME/.asdf/installs/ruby/truffleruby-19.2.0/bin"
export PATH="$PATH:$HOME/.asdf/installs/ruby/truffleruby-19.2.0/bin"
export PATH="$PATH:$HOME/.cargo/bin"
export PATH="$PATH:$HOME/.gem/ruby/2.4.0/bin"
export PATH="$PATH:$HOME/.gem/ruby/2.5.0/bin"
export PATH="$PATH:$HOME/.gem/ruby/2.6.0/bin"
export PATH="$PATH:$HOME/.gem/ruby/2.7.0/bin"
export PATH="$PATH:$HOME/.homebrew/bin"
export PATH="$PATH:$HOME/.local/bin"
export PATH="$PATH:$HOME/.local/share/gem/ruby/3.0.0/bin"
export PATH="$PATH:$HOME/Library/Python/3.8/bin/"
export PATH="$PATH:$HOME/bin"
export PATH="$PATH:$HOME/go/bin"
export PATH="$PATH:/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin"
export PATH="$PATH:/usr/local/sbin"
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

# Todo.txt
export TODO_DIR="$HOME/gdrive/todo/"
export TODO_FILE="$HOME/gdrive/todo/todo.txt"
export DONE_FILE="$HOME/gdrive/todo/done.txt"

# nnn Environment variables
export NNN_OPTS="aedF"
export NNN_BMS="D:~/Documents;d:~/Downloads;g:~/git;h:~;"
