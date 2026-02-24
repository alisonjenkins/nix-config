{ pkgs, ... }:

let
  tomlFormat = pkgs.formats.toml { };

  settings = {
    scan_batch_size = 10;
    favorite_apps = [ ];

    keybindings = {
      "control-k" = "previous_entry";
      "control-j" = "next_entry";
    };

    theme = {
      background = "#1F1F1FF2";

      border = {
        color = "#A6A6A61A";
        width = 1.0;
        radius = [ 20 20 20 20 ];
      };

      prompt = {
        background = "#00000000";
        font_size = 18;
        icon_size = 28;
        padding = [ 8 8 8 8 ];
        margin = [ 15 15 15 15 ];
        placeholder_color = "#FFFFFF80";
        text_color = "#F2F2F2FF";
        border = {
          color = "#00000000";
          width = 0.0;
          radius = [ 20 20 20 20 ];
        };
      };

      separator = {
        color = "#A6A6A61A";
        width = 1;
        padding = 10;
        radius = 0.0;
      };

      launchpad = {
        padding = 10.0;
        entry = {
          background = "#1F1F1FF2";
          focus_highlight = "#FFFFFF1F";
          hover_highlight = "#FFFFFF14";
          font_size = 14;
          secondary_font_size = 12;
          main_text = "#F2F2F2FF";
          secondary_text = "#FFFFFF80";
          padding = [ 10 10 10 10 ];
          height = 58.0;
          icon_size = 32;
          border = {
            color = "#00000000";
            width = 0.0;
            radius = [ 20 20 20 20 ];
          };
        };
      };
    };
  };
in
{
  home.packages = [ pkgs.lucien ];

  xdg.configFile."lucien/preferences.toml".source =
    tomlFormat.generate "preferences.toml" settings;
}
