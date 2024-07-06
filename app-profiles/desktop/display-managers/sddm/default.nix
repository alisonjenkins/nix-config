{
  config,
  lib,
  pkgs,
  ...
}: {
  services = {
    displayManager = {
      autoLogin.enable = false;
      sddm = {
        enable = true;
        theme = "breeze";
        wayland.enable = true;
      };
    };
  };
}
