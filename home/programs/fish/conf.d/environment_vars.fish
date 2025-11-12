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
# Set fish_user_paths as a universal variable in the correct order
# This will persist across sessions and override any stale cached values
if test (uname -s) = "Darwin"
    # macOS: Nix paths come before Homebrew to avoid conflicts
    set -Ux fish_user_paths \
        "/etc/profiles/per-user/$USER/bin" \
        /run/current-system/sw/bin \
        /nix/var/nix/profiles/default/bin \
        "$HOME/.cargo/bin" \
        "$HOME/.local/bin" \
        "$HOME/bin" \
        "$HOME/go/bin" \
        /opt/homebrew/bin \
        /usr/local/sbin \
        "$HOME/.krew/bin"
else
    # Linux/NixOS: system paths first
    set -Ux fish_user_paths \
        /run/current-system/sw/bin \
        "$HOME/.cargo/bin" \
        "$HOME/.local/bin" \
        "$HOME/bin" \
        "$HOME/go/bin" \
        /usr/local/sbin \
        "$HOME/.krew/bin"
end

# nnn Environment variables
set -gx NNN_OPTS "aedF"
set -gx NNN_BMS "D:~/Documents;d:~/Downloads;g:~/git;h:~;"
