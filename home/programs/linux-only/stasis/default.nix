{pkgs, ...}: {
  home.packages = [
    pkgs.stasis
  ];

  home.file = {
    ".config/stasis/stasis.rune".text = (import ./stasis.rune.nix { pkgs = pkgs; });
  };

  systemd.user.services.stasis = {
    Unit = {
      Description = "Stasis Wayland Idle Manager";
      After = [ "graphical-session.target" ];
      Wants = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.stasis}/bin/stasis";
      Restart = "always";
      RestartSec = 5;
      Environment = "WAYLAND_DISPLAY=wayland-0";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}

