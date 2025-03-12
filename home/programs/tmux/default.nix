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

  programs.tmux =
    let
      shell = if pkgs.stdenv.isDarwin then "/etc/profiles/per-user/${username}/bin/zsh" else "${pkgs.zsh}/bin/zsh";
    in
    {
      baseIndex = 1;
      enable = true;
      escapeTime = 0;
      extraConfig = import ./tmux.conf.nix { inherit shell; };
      keyMode = "vi";
      newSession = true;
      prefix = "C-a";
      shell = shell;

      plugins = with pkgs; [
        # tmuxPlugins.sensible
        tmuxPlugins.pain-control
        tmuxPlugins.prefix-highlight
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
