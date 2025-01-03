{ pkgs, ... }: {
  home.file =
    let
      ghostty-shaders = pkgs.stdenv.mkDerivation {
        name = "ghostty-shaders";
        src = pkgs.fetchFromGitHub {
          owner = "m-ahdal";
          repo = "ghostty-shaders";
          rev = "ec29c83d81ebe7e9ca9250b3c799a2d700c1cca8";
          sha256 = "sha256-8D0H13JzCTzgzjzjERQG8ruayeHn1CPcRsd+KtC6nj4=";
        };

        installPhase = ''
          mkdir -p $out
          mv *.glsl $out
        '';
      };
      font-family = "FiraCode Nerd Font Mono";
      zsh = "${pkgs.zsh}/bin/zsh";
    in
    {
      ".config/ghostty/config".text = ''
        adjust-underline-position = 40%
        adjust-underline-thickness = -60%
        background-opacity = 0.9
        clipboard-paste-protection = false
        command = ${zsh} -l -c 'tmux attach ; tmux'
        confirm-close-surface = false
        cursor-style = block
        cursor-style-blink = false
        custom-shader = ${ghostty-shaders}/matrix-hallway.glsl
        font-family = ${font-family}
        font-size = 13
        font-style = Regular
        font-thicken = true
        palette = 12=#344CFF
        palette = 4=#3D52E2
        selection-background = 1d3c3b
        selection-foreground = eeeeee
        theme = GruvboxDarkHard
        title = Ghostty
        unfocused-split-opacity = 1.0
        window-decoration = false
        window-height = 45
        window-padding-x = 4
        window-width = 120
      '';
    };
}
