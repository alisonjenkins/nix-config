# Vi mode
fish_vi_key_bindings

# Set the history file location
set -g fish_history_dir ~/.local/share/fish

# Interactive shell settings
set -g fish_greeting ''

# Better history search (up/down arrows)
bind -M insert \e\[A history-prefix-search-backward
bind -M insert \e\[B history-prefix-search-forward

# Emulate some zsh-like behaviors
set -g fish_key_bindings fish_vi_key_bindings
