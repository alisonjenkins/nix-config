# Cache OS name once to avoid repeated uname subprocess calls
# (aliases.fish also checks this variable and sets it if not yet set)
set -q _os_name; or set -g _os_name (uname -s)

# XDG Config
if not set -q XDG_CONFIG_HOME
    set -gx XDG_CONFIG_HOME "$HOME/.config"
end

# SSH agent
if test "$_os_name" = Linux
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
if test "$_os_name" = Darwin
    set -gx HOMEBREW_CASK_OPTS '--appdir=/Applications'
    # Skip optional git index locks during read operations (git status, git branch).
    # Reduces AV-scanned file writes on every prompt render.
    set -gx GIT_OPTIONAL_LOCKS 0
end

# PATH setup — global (not universal) since we rebuild every startup anyway,
# avoiding a fish_variables disk write on each shell open.
if test "$_os_name" = Darwin
    # macOS: Nix paths come before Homebrew to avoid conflicts
    set -g fish_user_paths \
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
    # Linux/NixOS: Only add user-specific paths, let NixOS manage system paths
    set -g fish_user_paths \
        "$HOME/.cargo/bin" \
        "$HOME/.local/bin" \
        "$HOME/bin" \
        "$HOME/go/bin" \
        "$HOME/.krew/bin"
end

# nnn Environment variables
set -gx NNN_OPTS "aedF"
set -gx NNN_BMS "D:~/Documents;d:~/Downloads;g:~/git;h:~;"
