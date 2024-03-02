{ config, lib, pkgs, ... }: {
  services.xserver = {
    enable = true;
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
