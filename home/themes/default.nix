{ pkgs
, ...
}: {
  imports = [
    # ./cava
  ];

  gtk = {
    enable = true;
    gtk4.theme = null; # Silence HM 26.05 migration warning (adopting new default)
    # iconTheme = {
    #   name = "Yaru-magenta-dark";
    #   package = pkgs.yaru-theme;
    # };
    #
    # theme = {
    #   name = "Tokyonight-Dark-B-LB";
    #   package = pkgs.tokyo-night-gtk;
    # };
    #
    # cursorTheme = {
    #   name = "Bibata-Modern-Classic";
    #   package = pkgs.bibata-cursors;
    # };
  };
}
