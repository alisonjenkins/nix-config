{ pkgs, ... }: {
  home.file = (if pkgs.stdenv.isLinux then
    let
      steam-autostart-silent = pkgs.stdenvNoCC.mkDerivation {
        name = "steam-autostart-silent";
        version = "0.0.1";
        dontUnpack = true;
        installPhase = ''
          cp "${pkgs.steam}/share/applications/steam.desktop" steam.desktop
          ${pkgs.gnused}/bin/sed -i 's#Exec=steam %U#Exec=steam -silent %U#' steam.desktop
          mkdir -p "$out/share/applications"
          cp steam.desktop "$out/share/applications/steam-autostart-silent.desktop"
        '';
      };
    in
    {
      ".config/autostart/1password.desktop".source = "${pkgs._1password-gui}/share/applications/1password.desktop";
      ".config/autostart/alacritty.desktop".source = "${pkgs.alacritty}/share/applications/Alacritty.desktop";
      ".config/autostart/firefox.desktop".source = "${pkgs.firefox}/share/applications/firefox.desktop";
      ".config/autostart/steam.desktop".source = "${steam-autostart-silent}/share/applications/steam-autostart-silent.desktop";
      ".config/autostart/vesktop.desktop".source = "${pkgs.vesktop}/share/applications/vesktop.desktop";
    } else { });
}
