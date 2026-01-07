{ ...
}: {
  imports = [
    ./aws
    ./base
    ./kubernetes
    ./media
  ];

  programs.dconf.enable = true;

  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };
}
