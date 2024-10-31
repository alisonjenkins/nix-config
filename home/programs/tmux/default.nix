{ pkgs
, username
, ...
}: {
  home.packages = [
    pkgs.tmux-sessionizer
  ];

  home.file =
    let
      home =
        if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
    in
    {
      ".config/tms/config.toml".text = ''
        [[search_dirs]]
        path = "${home}/git"
        depth = 10
      '';
    };

  programs.tmux = {
    enable = true;
    newSession = true;
    prefix = "C-a";
    # shell = if pkgs.stdenv.isDarwin then "/etc/profiles/per-user/${username}/bin/zsh" else "${pkgs.zsh}/bin/zsh";
    baseIndex = 1;
    terminal = "tmux-256color";
    escapeTime = 0;

    extraConfig = import ./tmux.conf.nix { inherit username; };
    keyMode = "vi";
    plugins = with pkgs; [
      tmuxPlugins.cpu
      tmuxPlugins.pain-control
      tmuxPlugins.prefix-highlight
      tmuxPlugins.sensible
      tmuxPlugins.sessionist
      {
        plugin = tmuxPlugins.catppuccin;
        extraConfig = ''
          set -g @catppuccin_window_right_separator "█ "
          set -g @catppuccin_window_number_position "right"
          set -g @catppuccin_window_middle_separator " | "

          set -g @catppuccin_window_default_fill "none"

          set -g @catppuccin_window_current_fill "all"

          set -g @catppuccin_status_modules_right "application session user host date_time"
          set -g @catppuccin_status_left_separator "█"
          set -g @catppuccin_status_right_separator "█"

          set -g @catppuccin_date_time_text "%Y-%m-%d %H:%M:%S"
        '';
      }
      {
        plugin = tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-boot 'on'
          set -g @continuum-save-interval '5' # minutes
        '';
      }
      {
        plugin = tmuxPlugins.resurrect;
        extraConfig = ''
          set -g @resurrect-strategy-nvim 'session'
          set -g @resurrect-capture-pane-contents 'on'
        '';
      }
      {
        plugin = tmuxPlugins.tmux-thumbs;
        extraConfig = ''
          set -g @thumbs-key F
          set -g @thumbs-osc52 1

          # if-shell -b '[ -z "$WAYLAND_DISPLAY" ] && ! uname | grep -q Darwin' \
          #   "set -g @thumbs-command 'echo -n {} | xclip -selection clipboard'
          # if-shell 'uname | grep -q Darwin' \
          #   "set -g @thumbs-command 'echo -n {} | pbcopy'
          # if-shell '[ -n "$WAYLAND_DISPLAY" ]' \
          #   "set -g @thumbs-command 'echo -n {} | wl-copy'
        '';
      }
      {
        plugin = tmuxPlugins.jump;
        extraConfig = ''
          set -g @jump-key 's'
        '';
      }
    ];
  };
}
