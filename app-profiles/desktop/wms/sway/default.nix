{
  pkgs,
  username,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    grim
    mako
    slurp
    wl-clipboard
    wofi
  ];

  security = {
    pam = {
      services = {
        ${username} = {
          enableKwallet = true;
        };
        swaylock = {};
      };
    };
    polkit = {
      enable = true;
    };
  };

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  security.pam.loginLimits = [
    { domain = "@users"; item = "rtprio"; type = "-"; value = 1; }
  ];
}
