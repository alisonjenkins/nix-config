{ ...
}: {
  imports = [
    ./base
    ./fonts
    ./media
  ];

  programs.dconf.enable = true;

  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };
}
