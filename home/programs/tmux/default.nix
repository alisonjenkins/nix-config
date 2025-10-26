
{ pkgs
, username
, github_clone_ssh_host_personal ? "github.com"
, github_clone_ssh_host_work ? "github.com"
, ...
}: {
  home.packages = [
    pkgs.tmux-sessionizer
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
