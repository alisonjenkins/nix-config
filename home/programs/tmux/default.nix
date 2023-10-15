{ config, pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    newSession = true;
    prefix = "C-a";
    plugins = with pkgs; [
      tmuxPlugins.cpu
      tmuxPlugins.pain-control
      tmuxPlugins.prefix-highlight
      tmuxPlugins.sessionist
      {
        plugin = tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '5' # minutes
          '';
      }
      {
        plugin = tmuxPlugins.resurrect;
        extraConfig = "set -g @resurrect-strategy-nvim 'session'";
      }
    ];
  };
  home.file = {
    ".tmux.conf".text = builtins.readFile ./tmux.conf;
  };
}

