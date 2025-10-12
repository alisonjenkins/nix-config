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
      { event = "after-resume"; command = "${pkgs.suspendScripts}/bin/suspend-resume '${bluetoothHeadsetMac}'"; }
      { event = "before-sleep"; command = "${pkgs.suspendScripts}/bin/suspend-pre"; }
      { event = "lock"; command = "${pkgs.lock-session}/bin/lock-session ${toString lockGracePeriodSeconds} ${toString lockFadeInSeconds}"; }
    ];

    timeouts = [
      { timeout = 900; command = "${pkgs.lock-session}/bin/lock-session ${toString idleLockGracePeriodSeconds} ${toString lockFadeInSeconds}"; }
    ];
  };
}
