{
    pkgs,
    tmux-catpuccin,
    ...
}: ''

set-option -g default-command "${pkgs.zsh}/bin/zsh"
run-shell ${pkgs.tmuxPlugins.sensible}/share/tmux-plugins/sensible/sensible.tmux

run-shell ${pkgs.tmuxPlugins.cpu}/share/tmux-plugins/cpu/cpu.tmux
run-shell ${pkgs.tmuxPlugins.pain-control}/share/tmux-plugins/pain-control/pain_control.tmux
run-shell ${pkgs.tmuxPlugins.prefix-highlight}/share/tmux-plugins/prefix-highlight/prefix_highlight.tmux
run-shell ${pkgs.tmuxPlugins.sessionist}/share/tmux-plugins/sessionist/sessionist.tmux

# tmuxplugin-catppuccin
# ---------------------
set -g @catppuccin_window_right_separator "█ "
set -g @catppuccin_window_number_position "right"
set -g @catppuccin_window_middle_separator " | "
set -g @catppuccin_window_default_fill "none"
set -g @catppuccin_window_current_fill "all"
set -g @catppuccin_status_modules_right "application session user host date_time"
set -g @catppuccin_status_left_separator "█"
set -g @catppuccin_status_right_separator "█"
set -g @catppuccin_date_time_text "%Y-%m-%d %H:%M:%S"
run-shell ${tmux-catpuccin}/catppuccin.tmux

# tmuxplugin-continuum
# ---------------------
# set -g @continuum-restore 'on'
# set -g @continuum-boot 'on'
# set -g @continuum-save-interval '5' # minutes
#
# run-shell /nix/store/2y1hg2v43yadfhc3l6swc2pv8iz1bha1-tmuxplugin-continuum-unstable-2022-01-25/share/tmux-plugins/continuum/continuum.tmux


# tmuxplugin-resurrect
# ---------------------
# set -g @resurrect-strategy-nvim 'session'
# set -g @resurrect-capture-pane-contents 'on'
#
# run-shell /nix/store/x1x21nihsfmdxban06vf97cyqxg8009w-tmuxplugin-resurrect-unstable-2022-05-01/share/tmux-plugins/resurrect/resurrect.tmux


# tmuxplugin-tmux-thumbs
# ---------------------
set -g @thumbs-key F
set -g @thumbs-osc52 1

# if-shell -b '[ -z "$WAYLAND_DISPLAY" ] && ! uname | grep -q Darwin' \
#   "set -g @thumbs-command 'echo -n {} | xclip -selection clipboard'
# if-shell 'uname | grep -q Darwin' \
#   "set -g @thumbs-command 'echo -n {} | pbcopy'
# if-shell '[ -n "$WAYLAND_DISPLAY" ]' \
#   "set -g @thumbs-command 'echo -n {} | wl-copy'

run-shell ${pkgs.tmuxPlugins.tmux-thumbs}/share/tmux-plugins/tmux-thumbs/tmux-thumbs.tmux


# tmuxplugin-jump
# ---------------------
set -g @jump-key 's'

run-shell ${pkgs.tmuxPlugins.jump}/share/tmux-plugins/jump/tmux-jump.tmux

# Settings

set  -g default-terminal "tmux-256color"
set  -g base-index      1
setw -g pane-base-index 1
set -g status-keys vi
set -g mode-keys   vi

# rebind main key: C-a
unbind C-b
set -g prefix C-a
bind -N "Send the prefix key through to the application" \
  C-a send-prefix

set  -g mouse             on
setw -g aggressive-resize on
setw -g clock-mode-style  24
set  -s escape-time       0
set  -g history-limit     2000
set -g @shell_mode 'vi'
set -g @prefix_highlight_show_copy_mode 'on'
set -g @prefix_highlight_copy_mode_attr 'fg=black,bg=yellow,bold' # default is 'fg=default,bg=yellow'
set -g allow-passthrough on
set -s set-clipboard off
setw -g monitor-activity on
set -g visual-activity off
set -g history-limit 100000
set-window-option -g automatic-rename on
set-option -g focus-events on
set-option -g set-titles on
set-option -g set-titles-string '[#S:#I #h] #W'
setw -g mode-keys vi
set-option -sa terminal-features ",''${TERM}*:RGB"

is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
bind-key -T copy-mode-vi 'v' send -X begin-selection
bind-key -T copy-mode-vi Escape send -X cancel
bind-key C-a last-window
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind r source-file ~/.config/tmux/tmux.conf \; display-message 'Reloaded ~/.tmux.conf!'
bind-key -n 'C-h' if-shell "$is_vim" 'send-keys C-h' 'select-pane -L'
bind-key -n 'C-j' if-shell "$is_vim" 'send-keys C-j' 'select-pane -D'
bind-key -n 'C-k' if-shell "$is_vim" 'send-keys C-k' 'select-pane -U'
bind-key -n 'C-l' if-shell "$is_vim" 'send-keys C-l' 'select-pane -R'
bind-key Space choose-session
bind C-o display-popup -E "tms"

if-shell -b '[ -z "$WAYLAND_DISPLAY" ] && ! uname | grep -q Darwin' \
    "bind -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel \"xclip -selection clipboard\""
if-shell 'uname | grep -q Darwin' \
    "bind -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel \"pbcopy\""
if-shell '[ -n "$WAYLAND_DISPLAY" ]' \
    "bind -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel \"wl-copy\""

set -g @shell_mode 'vi'
set -g @prefix_highlight_show_copy_mode 'on'
set -g @prefix_highlight_copy_mode_attr 'fg=black,bg=yellow,bold' # default is 'fg=default,bg=yellow'
set -g allow-passthrough on
set -s set-clipboard off
setw -g monitor-activity on
set -g visual-activity off
set -g history-limit 100000
set-window-option -g automatic-rename on
set-option -g focus-events on
set-option -g set-titles on
set-option -g set-titles-string '[#S:#I #h] #W'
setw -g mode-keys vi
set-option -sa terminal-features ",''${TERM}*:RGB"

is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|n?vim?x?)(diff)?$'"
bind-key -T copy-mode-vi 'v' send -X begin-selection
bind-key -T copy-mode-vi Escape send -X cancel
bind-key C-a last-window
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind r source-file ~/.config/tmux/tmux.conf \; display-message 'Reloaded ~/.tmux.conf!'
bind-key -n 'C-h' if-shell "$is_vim" 'send-keys C-h' 'select-pane -L'
bind-key -n 'C-j' if-shell "$is_vim" 'send-keys C-j' 'select-pane -D'
bind-key -n 'C-k' if-shell "$is_vim" 'send-keys C-k' 'select-pane -U'
bind-key -n 'C-l' if-shell "$is_vim" 'send-keys C-l' 'select-pane -R'
bind-key Space choose-session
bind C-o display-popup -E "tms"

if-shell -b '[ -z "$WAYLAND_DISPLAY" ] && ! uname | grep -q Darwin' \
    "bind -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel \"xclip -selection clipboard\""
if-shell 'uname | grep -q Darwin' \
    "bind -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel \"pbcopy\""
if-shell '[ -n "$WAYLAND_DISPLAY" ]' \
    "bind -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel \"wl-copy\""

new-session
''
