{
  bluetoothHeadsetMac ? "",
  lib,
  pkgs,
  # Total idle seconds before the displays are powered off (DPMS) via niri.
  # Fires independently of the 900s lock timeout, so on niri hosts a locked,
  # idle screen no longer stays lit indefinitely. Set to null to disable.
  # Default lives solely in home/home-common.nix
  # (`_module.args.screenOffTimeoutSeconds`) — the module system resolves this
  # arg from _module.args, so a function-default here would be dead code.
  screenOffTimeoutSeconds,
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
    ] ++ lib.optionals (screenOffTimeoutSeconds != null) [
      {
        timeout = screenOffTimeoutSeconds;
        command = "${pkgs.niri}/bin/niri msg action power-off-monitors";
        resumeCommand = "${pkgs.niri}/bin/niri msg action power-on-monitors";
      }
    ];
  };
}
