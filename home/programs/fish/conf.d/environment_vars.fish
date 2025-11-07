# XDG Config
if not set -q XDG_CONFIG_HOME
    set -gx XDG_CONFIG_HOME "$HOME/.config"
end

# SSH agent
if test (uname -s) = "Linux"
    if test -z "$SSH_AUTH_SOCK"
        set -gx SSH_AUTH_SOCK "$XDG_RUNTIME_DIR/ssh-agent.socket"
    end
end

# AWS vault options
if test -x /usr/bin/kwalletd5
    set -gx AWS_VAULT_BACKEND kwallet
end

# Set default editor
set -gx EDITOR nvim

# Go Path
set -gx GOPATH "$HOME/go"
set -gx GOBIN "$HOME/go/bin"

# McFly options
set -gx MCFLY_FUZZY 2
set -gx MCFLY_KEY_SCHEME vim
set -gx MCFLY_RESULTS 50

# Load secret environment variables
if test -f ~/.secret_envvars
    source ~/.secret_envvars
end

# Homebrew on Mac
if test (uname -s) = "Darwin"
    set -gx HOMEBREW_CASK_OPTS '--appdir=/Applications'
end

# PATH setup
# Prepend system paths first to avoid wrong architecture binaries
fish_add_path -gP /run/current-system/sw/bin
fish_add_path -g "$HOME/.cargo/bin"
fish_add_path -g /opt/homebrew/bin
fish_add_path -g "$HOME/.local/bin"
fish_add_path -g "$HOME/bin"
fish_add_path -g "$HOME/go/bin"
fish_add_path -g /usr/local/sbin
fish_add_path -g "$HOME/.krew/bin"

# nnn Environment variables
set -gx NNN_OPTS "aedF"
set -gx NNN_BMS "D:~/Documents;d:~/Downloads;g:~/git;h:~;"
