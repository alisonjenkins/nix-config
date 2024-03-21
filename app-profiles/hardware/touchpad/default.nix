{
  config,
  lib,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    libinput-gestures
  ];

  services.xserver.libinput.touchpad = {
    tapping = true;
  };
}
