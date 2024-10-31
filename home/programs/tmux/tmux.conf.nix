{ shell }: ''
  set -g @shell_mode 'vi'
  set -g @prefix_highlight_show_copy_mode 'on'
  set -g @prefix_highlight_copy_mode_attr 'fg=black,bg=yellow,bold' # default is 'fg=default,bg=yellow'
  set-option -g default-command ${shell}
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
''
