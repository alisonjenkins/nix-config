{ pkgs, ... }: {
  home.file = (if pkgs.stdenv.isLinux then
    let
      steam-autostart-silent = pkgs.stdenvNoCC.mkDerivation {
        name = "steam-autostart-silent";
        version = "0.0.1";
        dontUnpack = true;
        installPhase = ''
          cp ${pkgs.steam}/share/applications/steam.desktop steam.desktop
          ${pkgs.gnused}/bin/sed -i 's#Exec=steam %U#Exec=steam -silent %U#' steam.desktop
          mkdir -p "$out/share/applications"
          cp steam.desktop "$out/share/applications/steam-autostart-silent.desktop"
        '';
        };

        _1password-gui-autostart-wayland = pkgs.stdenvNoCC.mkDerivation {
          name = "_1password-gui-autostart-silent";
          version = "0.0.1";
          dontUnpack = true;
          installPhase = ''
            cp ${pkgs._1password-gui}/share/applications/1password.desktop 1password.desktop
            ${pkgs.gnused}/bin/sed -i 's#Exec=1password %U#Exec=1password --ozone-platform-hint=auto %U#' 1password.desktop
            mkdir -p "$out/share/applications"
            cp 1password.desktop "$out/share/applications/1password.desktop"
          '';
        };
    in
    {
      ".config/autostart/1password.desktop".source = "${_1password-gui-autostart-wayland}/share/applications/1password.desktop";
      ".config/autostart/alacritty.desktop".source = "${pkgs.alacritty}/share/applications/Alacritty.desktop";
      ".config/autostart/ghostty.desktop".source = "${pkgs.ghostty}/share/applications/Ghostty.desktop";
      ".config/autostart/firefox.desktop".source = "${pkgs.firefox}/share/applications/firefox.desktop";
      ".config/autostart/steam.desktop".source = "${steam-autostart-silent}/share/applications/steam-autostart-silent.desktop";
      ".config/autostart/vesktop.desktop".source = "${pkgs.vesktop}/share/applications/vesktop.desktop";
    } else { });
}
