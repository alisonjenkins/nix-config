{ pkgs, ... }: let
  # Most autostart entries (steam, discord, keybase-gui, zapzap) are
  # x86_64-only — gate the whole block to skip cleanly on
  # aarch64-linux hosts like ali-mba-linux.
  isLinuxX86 = pkgs.stdenv.isLinux && pkgs.stdenv.hostPlatform.isx86_64;
in {
  home = {
    packages = if isLinuxX86 then with pkgs; [
      zapzap
    ] else [];
  };

  home.file = (if isLinuxX86 then
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
          # Electron picks its password store from the desktop environment:
          # KDE* -> kwallet, GNOME/XFCE/... -> libsecret, anything else ->
          # basic_text (plaintext, and it refuses to reuse the old key). On
          # niri XDG_CURRENT_DESKTOP is "niri", so Signal downgrades itself
          # to basic_text and errors out with "the OS encryption keyring
          # backend has changed from kwallet6 to basic_text". This host keeps
          # its secrets in kwallet (see the ali-desktop portal Secret config),
          # so name the backend explicitly.
          ${pkgs.gnused}/bin/sed -i 's#Exec=signal-desktop#Exec=signal-desktop --password-store=kwallet6 --enable-gpu --ignore-gpu-blocklist --ozone-platform-hint=auto --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,PipeWireCamera,WebRTCPipeWireCapturer#' signal.desktop
          mkdir -p "$out/share/applications"
          cp signal.desktop "$out/share/applications/signal.desktop"
        '';
      };
    in
    {
      ".config/autostart/discord.desktop".source = "${pkgs.discord}/share/applications/discord.desktop";
      ".config/autostart/element-desktop.desktop".source = "${pkgs.element}/share/applications/element-desktop.desktop";
      ".config/autostart/ghostty.desktop".source = "${pkgs.ghostty}/share/applications/com.mitchellh.ghostty.desktop";
      ".config/autostart/keybase.desktop".source = "${pkgs.keybase-gui}/share/applications/keybase.desktop";
      ".config/autostart/obsidian.desktop".source = "${pkgs.obsidian}/share/applications/obsidian.desktop";
      ".config/autostart/signal.desktop".source = "${signal-gpu-accel}/share/applications/signal.desktop";
      ".local/share/applications/signal.desktop".source = "${signal-gpu-accel}/share/applications/signal.desktop";
      # `steam -silent` starts the client minimised to the system tray instead
      # of throwing its window in front of whatever you were doing at login.
      ".config/autostart/steam.desktop".source = "${steam-autostart-silent}/share/applications/steam-autostart-silent.desktop";
      ".config/autostart/zapzap.desktop".source = "${pkgs.zapzap}/share/applications/com.rtosta.zapzap.desktop";
    } else { });
}
