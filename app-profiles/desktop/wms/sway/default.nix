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
  ];

  security.pam.services.${username}.enableKwallet = true;

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  security.pam.loginLimits = [
    { domain = "@users"; item = "rtprio"; type = "-"; value = 1; }
  ];
}
