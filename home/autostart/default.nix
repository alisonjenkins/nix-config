{ pkgs, ... }: {
  home = {
    packages = if pkgs.stdenv.isLinux then with pkgs; [
      whatsie
    ] else [];
  };

  home.file = (if pkgs.stdenv.isLinux then
    let
      steam-autostart-silent = pkgs.stdenvNoCC.mkDerivation {
        name = "steam-autostart-silent";
        version = "0.0.1";
        dontUnpack = true;
        installPhase = ''
          cp "${pkgs.steam}/share/applications/steam.desktop" steam.desktop
          ${pkgs.gnused}/bin/sed -i 's#Exec=steam %U#Exec=steam -silent %U#' steam.desktop
          # ${pkgs.gnused}/bin/sed -i 's#^$#NotShowIn=niri\n#' steam.desktop
          mkdir -p "$out/share/applications"
          cp steam.desktop "$out/share/applications/steam-autostart-silent.desktop"
        '';
      };
    in
    {
      ".config/autostart/1password.desktop".source = "${pkgs._1password-gui}/share/applications/1password.desktop";
      ".config/autostart/element-desktop.desktop".source = "${pkgs.element}/share/applications/element-desktop.desktop";
      ".config/autostart/firefox.desktop".source = "${pkgs.firefox}/share/applications/firefox.desktop";
      ".config/autostart/ghostty.desktop".source = "${pkgs.ghostty}/share/applications/com.mitchellh.ghostty.desktop";
      ".config/autostart/keybase.desktop".source = "${pkgs.keybase-gui}/share/applications/keybase.desktop";
      ".config/autostart/obsidian.desktop".source = "${pkgs.obsidian}/share/applications/obsidian.desktop";
      ".config/autostart/signal-desktop.desktop".source = "${pkgs.signal-desktop}/share/applications/signal.desktop";
      ".config/autostart/steam.desktop".source = "${steam-autostart-silent}/share/applications/steam-autostart-silent.desktop";
      ".config/autostart/vesktop.desktop".source = "${pkgs.vesktop}/share/applications/vesktop.desktop";
      ".config/autostart/whatsie.desktop".source = "${pkgs.whatsie}/share/applications/whatsie.desktop";
      # ".config/autostart/discord-canary.desktop".source = "${pkgs.discord-canary}/share/applications/discord-canary.desktop";
    } else { });
}
