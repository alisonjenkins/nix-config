{ pkgs, ... }: {
  home.packages = with pkgs; [
    brightnessctl
  ];

  services.swayidle = let
    lockCommand = "lock-session";
  in {
    enable = true;

    extraArgs = [
      "-w" # Wait for the before-sleep commands to complete before sleeping
    ];

    events = let
      lockGracePeriodSeconds = 0;
      lockFadeInSeconds = 1;
    in [
      { event = "after-resume"; command = "suspend-resume '${bluetoothHeadsetMac}'"; }
      { event = "before-sleep"; command = "suspend-pre"; }
      { event = "lock"; command = "lock-session ${lockGracePeriodSeconds} ${lockFadeInSeconds}"; }
    ];

    timeouts = let
      lockFadeInSeconds = 1;
      lockGracePeriodSeconds = 30;
    in [
      { timeout = 900; command = "lock-session ${lockGracePeriodSeconds} ${lockFadeInSeconds}"; }
    ];
  };
}
