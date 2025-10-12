{
  bluetoothHeadsetMac ? "",
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    brightnessctl
  ];

  services.swayidle =
  let
      lockGracePeriodSeconds = 0;
      lockFadeInSeconds = 1;
      idleLockGracePeriodSeconds = 30;
  in {
    enable = true;

    extraArgs = [
      "-w" # Wait for the before-sleep commands to complete before sleeping
    ];

    events = [
      { event = "after-resume"; command = "suspend-resume '${bluetoothHeadsetMac}'"; }
      { event = "before-sleep"; command = "suspend-pre"; }
      { event = "lock"; command = "lock-session ${toString lockGracePeriodSeconds} ${toString lockFadeInSeconds}"; }
    ];

    timeouts = [
      { timeout = 900; command = "lock-session ${toString idleLockGracePeriodSeconds} ${toString lockFadeInSeconds}"; }
    ];
  };
}
