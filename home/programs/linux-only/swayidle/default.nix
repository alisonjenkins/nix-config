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

    events = [
      { event = "before-sleep"; command = lockCommand; }
      { event = "lock"; command = lockCommand; }
    ];

    timeouts = [
      { timeout = 900; command = lockCommand; }
    ];
  };
}
