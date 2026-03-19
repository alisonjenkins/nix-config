{ pkgs, lib, config, ... }:

{
  programs.tofi = {
    enable = true;

    settings = {
      # Performance options
      late-keyboard-init = true;
      ascii-input = true;

      # Behavior options
      history = true;
      matching-algorithm = "fuzzy";
      auto-accept-single = true;
      require-match = true;
      drun-launch = true;

      # Soy Milk theme
      # Font (mkForce to override Stylix)
      font = lib.mkForce "Fredoka One";
      font-size = lib.mkForce 20;

      # Window style
      horizontal = true;
      anchor = "top";
      width = "100%";
      height = 48;
      outline-width = lib.mkForce 0;
      border-width = lib.mkForce 0;
      min-input-width = 120;
      result-spacing = 30;
      padding-top = 8;
      padding-bottom = 0;
      padding-left = 20;
      padding-right = 0;

      # Text style (mkForce to override Stylix)
      prompt-text = "\"Can I have a\"";
      prompt-padding = 30;

      background-color = lib.mkForce "#fff0dc";
      text-color = lib.mkForce "#4280a0";

      prompt-color = lib.mkForce "#4280a0";
      prompt-background = lib.mkForce "#eebab1";
      prompt-background-padding = "4, 10";
      prompt-background-corner-radius = 12;

      input-color = "#e1666a";
      input-background = lib.mkForce "#f4cf42";
      input-background-padding = "4, 10";
      input-background-corner-radius = 12;

      default-result-background = lib.mkForce "#00000000";

      alternate-result-background = "#b8daf3";
      alternate-result-background-padding = "4, 10";
      alternate-result-background-corner-radius = 12;

      outline-color = lib.mkForce "#00000000";
      border-color = lib.mkForce "#00000000";
      placeholder-color = lib.mkForce "#FFFFFFA8";

      selection-color = lib.mkForce "#f0d2af";
      selection-background = lib.mkForce "#da5d64";
      selection-background-padding = "4, 10";
      selection-background-corner-radius = 12;
      selection-match-color = "#fff";

      clip-to-padding = false;

      # Misc
      hide-cursor = true;
      text-cursor = false;
    };
  };
}
