{ shell }: ''
  set-option -g default-command ${shell}
  set-option -g display-time 4000
  set-option -g focus-events on
  set-option -g focus-events on
  set-option -g history-limit 50000
  set-option -g set-titles on
  set-option -g set-titles-string '[#S:#I #h] #W'
  set-option -g status-keys emacs
  set-option -s escape-time 0
  set-option -sa terminal-features ",''${TERM}*:RGB"
  set-option status-interval 5

  # required (only) on OS X
  if is_osx && command_exists "reattach-to-user-namespace" && option_value_not_changed "default-command" ""; then
    tmux set-option -g default-command "reattach-to-user-namespace -l {shell}"
  fi

  set-window-option -g aggressive-resize on

  # set -g status-right '#{prefix_highlight} | %a %Y-%m-%d %H:%M'
  set -g mouse on
  set -g @prefix_highlight_copy_mode_attr 'fg=black,bg=yellow,bold' # default is 'fg=default,bg=yellow'
  set -g @prefix_highlight_show_copy_mode 'on'
  set -g @shell_mode 'vi'
  set -g default-terminal "tmux-256color"
  set -g allow-passthrough on
  set -g history-limit 100000
  set -g visual-activity off
  set -g visual-bell off
  set -g visual-silence on
  set -s set-clipboard off
  set-window-option -g automatic-rename on
  setw -g mode-keys vi
  setw -g monitor-activity on

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
