{ config, lib, pkgs, ... }: {
  services.xserver = {
    displayManager = {
      autoLogin.enable = false;
      sddm = {
        enable = true;
        theme = "breeze";
      };
    };
  };
}
