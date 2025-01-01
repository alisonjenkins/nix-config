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
      ".config/autostart/discord.desktop".source = "${pkgs.discord-canary}/share/applications/discord-canary.desktop";
      ".config/autostart/firefox.desktop".source = "${pkgs.firefox}/share/applications/firefox.desktop";
      ".config/autostart/ghostty.desktop".source = "${pkgs.ghostty}/share/applications/com.mitchellh.ghostty.desktop";
      ".config/autostart/steam.desktop".source = "${steam-autostart-silent}/share/applications/steam-autostart-silent.desktop";
    } else { });
}
