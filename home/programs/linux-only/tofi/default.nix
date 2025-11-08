{ pkgs, config, ... }:

{
  programs.tofi = {
    enable = true;

    settings = {
      # Performance options (most important)
      # font = "${pkgs.nerd-fonts.fira-code}/share/fonts/truetype/NerdFonts/FiraCodeNerdFontMono-Regular.ttf";
      late-keyboard-init = true;
      ascii-input = true;

      # Behavior options for efficiency
      history = true;
      matching-algorithm = "fuzzy";
      auto-accept-single = true;
      require-match = true;
      drun-launch = true;

      # Performance tweaks
      num-results = 10;

      # Theme using Stylix colors
      # font-size = 12;
      # background-color = "#${config.lib.stylix.colors.base00}";
      text-color = "#${config.lib.stylix.colors.base05}";
      # prompt-color = "#${config.lib.stylix.colors.base0D}";
      # selection-color = "#${config.lib.stylix.colors.base0B}";
      border-width = 2;
      # border-color = "#${config.lib.stylix.colors.base0D}";
      outline-width = 0;

      # Layout
      width = "100%";
      height = "100%";
      padding-top = "35%";
      padding-bottom = "35%";
      padding-left = "35%";
      padding-right = "35%";

      # Misc
      hide-cursor = true;
      text-cursor = false;
    };
  };
}
