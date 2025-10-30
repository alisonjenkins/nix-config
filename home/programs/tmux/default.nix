
{ pkgs
, username
, github_clone_ssh_host_personal ? "github.com"
, github_clone_ssh_host_work ? "github.com"
, ...
}: {
  home.packages = [
    pkgs.tmux-sessionizer
    (pkgs.writeShellScriptBin "tmux-smart-kill-session" ''
      #!/bin/bash
      
      # If called with a session name as argument (from choose-session), use that
      # Otherwise, use the current session
      if [ $# -eq 1 ]; then
        target_session="$1"
        current_session=$(tmux display-message -p '#S')
      else
        current_session=$(tmux display-message -p '#S')
        target_session="$current_session"
      fi
      
      # Get list of all sessions
      all_sessions=$(tmux list-sessions -F '#S')
      
      # Count total sessions
      session_count=$(echo "$all_sessions" | wc -l)
      
      # If there's only one session, just kill it (this will exit tmux)
      if [ "$session_count" -eq 1 ]; then
        tmux kill-session -t "$target_session"
        exit 0
      fi
      
      # If we're killing the current session, we need to switch first
      if [ "$target_session" = "$current_session" ]; then
        # Get the next session to switch to (first session that's not current)
        next_session=$(echo "$all_sessions" | grep -v "^$current_session$" | head -n 1)
        
        # Switch to the next session first
        if [ -n "$next_session" ]; then
          tmux switch-client -t "$next_session"
        fi
      fi
      
      # Kill the target session
      tmux kill-session -t "$target_session"
    '')
  ];

  home.file =
    let
      inherit github_clone_ssh_host_personal github_clone_ssh_host_work;

      home =
        if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";

      tmux-catpuccin = pkgs.stdenv.mkDerivation rec {
        name = "tmux-catpuccin";
        version = "2.1.3";
        src = pkgs.fetchFromGitHub {
          owner = "catppuccin";
          repo = "tmux";
          tag = "v${version}";
          hash = "sha256-Is0CQ1ZJMXIwpDjrI5MDNHJtq+R3jlNcd9NXQESUe2w=";
        };

        installPhase = ''
        mkdir -p $out
        cp -R $src/* $out/
        '';
      };
    in
    {
      ".config/tms/config.toml".text = ''
        [[search_dirs]]
        path = "${home}/git"
        depth = 10

        [[github_profiles]]
        name = "personal"
        credentials_command = "op item get \"tmux-sessionizer - personal repos FAT\" --fields label=password --reveal --cache"
        clone_url_ssh = "${github_clone_ssh_host_personal}"
        clone_root_path = "~/git/personal"
        clone_method = "SSH"

        [[github_profiles]]
        name = "work"
        credentials_command = "op item get \"tmux-sessionizer - work repos FAT\" --fields label=password --reveal --cache"
        clone_url_ssh = "${github_clone_ssh_host_work}"
        clone_root_path = "~/git/work"
        clone_method = "SSH"
      '';
      ".config/tmux/tmux.conf".text = import ./tmux.conf.nix {inherit pkgs; inherit tmux-catpuccin;};
    };
}
