
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
      '';
      ".config/tmux/tmux.conf".text = import ./tmux.conf.nix {inherit pkgs; inherit tmux-catpuccin;};
    };
}
