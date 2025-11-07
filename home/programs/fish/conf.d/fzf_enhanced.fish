# Enhanced FZF configuration for Fish
# This works with the fzf.fish plugin

# FZF options
set -gx FZF_DEFAULT_OPTS "--height 40% --layout=reverse --border --inline-info"

# Use fd for file search if available
if type -q fd
    set -gx FZF_DEFAULT_COMMAND 'fd --type f --hidden --follow --exclude .git'
    set -gx FZF_CTRL_T_COMMAND "$FZF_DEFAULT_COMMAND"
    set -gx FZF_ALT_C_COMMAND 'fd --type d --hidden --follow --exclude .git'
else if type -q fdfind
    set -gx FZF_DEFAULT_COMMAND 'fdfind --type f --hidden --follow --exclude .git'
    set -gx FZF_CTRL_T_COMMAND "$FZF_DEFAULT_COMMAND"
    set -gx FZF_ALT_C_COMMAND 'fdfind --type d --hidden --follow --exclude .git'
end

# Use bat for preview if available
if type -q bat
    set -gx FZF_CTRL_T_OPTS "--preview 'bat --color=always --line-range :500 {}'"
else if type -q batcat
    set -gx FZF_CTRL_T_OPTS "--preview 'batcat --color=always --line-range :500 {}'"
end

# fzf.fish plugin configuration
set -U fzf_fd_opts --hidden --exclude=.git
set -U fzf_preview_dir_cmd eza --all --color=always
if type -q bat
    set -U fzf_preview_file_cmd bat --color=always
else if type -q batcat
    set -U fzf_preview_file_cmd batcat --color=always
end

# Key bindings for fzf.fish (these will be set by the plugin)
# Ctrl+R - Search command history
# Ctrl+Alt+F - Search files
# Ctrl+Alt+S - Search git status files
# Ctrl+Alt+L - Search git log
# Ctrl+Alt+P - Search processes
# Ctrl+V - Search environment variables
