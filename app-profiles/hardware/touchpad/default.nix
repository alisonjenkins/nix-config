{ pkgs
, ...
}: {
  environment.systemPackages = with pkgs; [
    libinput-gestures
  ];

  services.libinput.touchpad = {
    tapping = true;
  };
}
