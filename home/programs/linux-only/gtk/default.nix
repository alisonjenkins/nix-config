{pkgs, ...}: {
  gtk = {
    enable = true;

    gtk4.theme = null;

    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
  };
}
