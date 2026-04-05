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

    events = {
      after-resume = "${pkgs.suspendScripts}/bin/suspend-resume '${bluetoothHeadsetMac}'";
      before-sleep = "${pkgs.suspendScripts}/bin/suspend-pre";
      lock = "${pkgs.lock-session}/bin/lock-session ${toString lockGracePeriodSeconds} ${toString lockFadeInSeconds}";
    };

    timeouts = [
      { timeout = 900; command = "${pkgs.lock-session}/bin/lock-session ${toString idleLockGracePeriodSeconds} ${toString lockFadeInSeconds}"; }
    ];
  };
}
