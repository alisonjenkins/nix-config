{ pkgs
, username
, ...
}:
{
  environment.systemPackages = with pkgs; [
    grim
    mako
    slurp
    wl-clipboard
  ];

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  security.pam.loginLimits = [
    { domain = "@users"; item = "rtprio"; type = "-"; value = 1; }
  ];
}
