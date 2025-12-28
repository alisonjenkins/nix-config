{ pkgs, ... }: {
  home = {
    packages = if pkgs.stdenv.isLinux then with pkgs; [
      zapzap
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

      signal-gpu-accel = pkgs.stdenvNoCC.mkDerivation {
        name = "signal-gpu-accel";
        version = "0.0.1";
        dontUnpack = true;
        installPhase = ''
          cp "${pkgs.signal-desktop}/share/applications/signal.desktop" signal.desktop
          ${pkgs.gnused}/bin/sed -i 's#Exec=signal-desktop#Exec=signal-desktop --enable-gpu#' signal.desktop
          mkdir -p "$out/share/applications"
          cp signal.desktop "$out/share/applications/signal.desktop"
        '';
      };
    in
    {
      ".config/autostart/1password.desktop".source = "${pkgs._1password-gui}/share/applications/1password.desktop";
      ".config/autostart/discord-canary.desktop".source = "${pkgs.discord-canary}/share/applications/discord-canary.desktop";
      ".config/autostart/element-desktop.desktop".source = "${pkgs.element}/share/applications/element-desktop.desktop";
      ".config/autostart/firefox.desktop".source = "${pkgs.firefox}/share/applications/firefox.desktop";
      ".config/autostart/ghostty.desktop".source = "${pkgs.ghostty}/share/applications/com.mitchellh.ghostty.desktop";
      ".config/autostart/keybase.desktop".source = "${pkgs.keybase-gui}/share/applications/keybase.desktop";
      ".config/autostart/obsidian.desktop".source = "${pkgs.obsidian}/share/applications/obsidian.desktop";
      ".config/autostart/signal.desktop".source = "${signal-gpu-accel}/share/applications/signal.desktop";
      ".config/autostart/steam.desktop".source = "${pkgs.steam}/share/applications/steam.desktop";
      ".config/autostart/vesktop.desktop".source = "${pkgs.vesktop}/share/applications/vesktop.desktop";
      ".config/autostart/zapzap.desktop".source = "${pkgs.zapzap}/share/applications/com.rtosta.zapzap.desktop";
      # ".config/autostart/steam.desktop".source = "${steam-autostart-silent}/share/applications/steam-autostart-silent.desktop";
    } else { });
}
