{
  pkgs,
  ...
}: let
  catpuccin_fuzzel_themes = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "fuzzel";
    rev = "0af0e26901b60ada4b20522df739f032797b07c3";
    hash = "sha256-XpItMGsYq4XvLT+7OJ9YRILfd/9RG1GMuO6J4hSGepg=";
  };
in {
  home.file = {
    ".config/fuzzel/fuzzel.ini".text = ''
    include=${catpuccin_fuzzel_themes}/themes/catppuccin-mocha/red.ini

    dpi-aware=yes
    gamma-correct=yes
    use-bold=yes
    '';
  };
}
