{
  pkgs,
  ...
}:
{
  wayland.windowManager.sway = {
    enable = if pkgs.stdenv.isLinux
      then true
      else false;
    config = {
      modifier = "Mod4";
      terminal = "ghostty"; 

      keybindings = let 
        modifier = config.wayland.windowManager.sway.config.modifier;
      in lib.mkOptionDefault {
      };

      startup = [
        {command = "firefox";}
        {command = "ghostty";}
        {command = "steam -silent";}
        {command = "vesktop";}
      ];
    };
  };
}
