{
  bluetoothHeadsetMac ? "",
  pkgs,
  ...
}: {
  home.packages = [
    pkgs.stasis
  ];

  home.file = {
    ".config/stasis/stasis.rune".text = (import ./stasis.rune.nix { inherit bluetoothHeadsetMac pkgs; });
  };

  systemd.user.services.stasis = {
    Unit = {
      Description = "Stasis Wayland Idle Manager";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.stasis}/bin/stasis";
      Restart = "always";
      RestartSec = 5;
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
