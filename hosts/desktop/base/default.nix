{ config, lib, pkgs, ... }:
{
  boot = {
    initrd.systemd.enable = true;
    plymouth = {
      enable = true;
      theme = "breeze";
    };
    kernelParams = [ "quiet" ];
  };

  services.xserver.displayManager.sddm = {
    enable = true;
    theme = "breeze";
  };

  environment.systemPackages = with pkgs; [
    fd
    git
    neovim
    nnn
    ripgrep
    tmux
  ];
}
