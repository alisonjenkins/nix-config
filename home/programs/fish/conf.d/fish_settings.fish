# Vi mode
fish_vi_key_bindings

# Set the history file location
set -g fish_history_dir ~/.local/share/fish

# Interactive shell settings
set -g fish_greeting ''

# Better history search (up/down arrows)
bind -M insert \e\[A history-prefix-search-backward
bind -M insert \e\[B history-prefix-search-forward

# Key bindings (fish 4.3+: global scope, not universal)
set -g fish_key_bindings fish_vi_key_bindings
# Clear old universal variable set by fish < 4.3
set --erase --universal fish_key_bindings

# Syntax highlighting and pager colors (fish 4.3+: global scope, not universal)
set --global fish_color_autosuggestion brblack
set --global fish_color_cancel -r
set --global fish_color_command normal
set --global fish_color_comment red
set --global fish_color_cwd green
set --global fish_color_cwd_root red
set --global fish_color_end green
set --global fish_color_error brred
set --global fish_color_escape brcyan
set --global fish_color_history_current --bold
set --global fish_color_host normal
set --global fish_color_host_remote yellow
set --global fish_color_normal normal
set --global fish_color_operator brcyan
set --global fish_color_param cyan
set --global fish_color_quote yellow
set --global fish_color_redirection cyan --bold
set --global fish_color_search_match white --background=brblack
set --global fish_color_selection white --bold --background=brblack
set --global fish_color_status red
set --global fish_color_user brgreen
set --global fish_color_valid_path --underline
set --global fish_pager_color_completion normal
set --global fish_pager_color_description yellow -i
set --global fish_pager_color_prefix normal --bold --underline
set --global fish_pager_color_progress brwhite --background=cyan
set --global fish_pager_color_selected_background -r
