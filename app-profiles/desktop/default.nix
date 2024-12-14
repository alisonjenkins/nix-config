{ ...
}: {
  imports = [
    ./aws
    ./base
    ./fonts
    ./kubernetes
    ./media
  ];

  programs.dconf.enable = true;

  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };
}
