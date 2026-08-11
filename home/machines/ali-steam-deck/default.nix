{ lib, ... }:
{
  # The Steam Deck runs Jovian's Gaming Mode (gamescope) and Plasma as its
  # desktop session — never niri. home/programs/linux-only is imported by
  # every Linux home config though, and noctalia's systemd user service is
  # bound to graphical-session.target, so without this the niri shell
  # autostarted inside Gaming Mode and the Plasma session.
  programs.noctalia.enable = lib.mkForce false;
  custom.niri.enable = lib.mkForce false;

  # No screen locking on the Deck. It is a handheld with no physical keyboard,
  # nothing installed provides an on-screen keyboard on the lock screen (KWin's
  # virtual keyboard is unconfigured and no maliit/squeekboard package is in
  # the closure), and Steam's own OSK cannot help: it needs the Steam client
  # and cannot draw above kscreenlocker. A lock screen therefore leaves the
  # device unusable until it is rebooted or reached over SSH.
  programs.plasma.kscreenlocker = {
    autoLock = false;
    lockOnResume = false;
  };

  # ...and unbind the manual lock shortcuts (Meta+L, Ctrl+Alt+L, the
  # Screensaver key) for the same reason: an empty key list is written to
  # kglobalshortcutsrc as "none".
  programs.plasma.shortcuts.ksmserver."Lock Session" = [ ];

  # swayidle comes from the same niri stack and locks the session after 900s
  # idle (and on the `lock` event) via lock-session — which is exactly the
  # lockout above, and it fires regardless of the Plasma settings. Its
  # screen-off action also shells out to `niri msg`, which does not exist in
  # a Plasma or gamescope session. Plasma handles idle and suspend through
  # powerdevil here.
  services.swayidle.enable = lib.mkForce false;

  # home/autostart launches a full desktop's worth of chat apps at login. On a
  # handheld that is a slow, noisy startup for apps that are not used here;
  # they stay available to launch by hand.
  home.file.".config/autostart/discord.desktop".enable = false;
  home.file.".config/autostart/element-desktop.desktop".enable = false;
  home.file.".config/autostart/ghostty.desktop".enable = false;
  home.file.".config/autostart/keybase.desktop".enable = false;
  home.file.".config/autostart/obsidian.desktop".enable = false;
  home.file.".config/autostart/signal.desktop".enable = false;
  home.file.".config/autostart/zapzap.desktop".enable = false;

  # keybase_autostart.desktop is written by run_keybase itself, not by
  # home/autostart, so there is no home.file entry to switch off — take the
  # path over with a hidden entry instead. (Its unit was failing at every
  # login here anyway: app-keybase_autostart@autostart.service.)
  home.file.".config/autostart/keybase_autostart.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Keybase
    Exec=true
    Hidden=true
    X-GNOME-Autostart-enabled=false
  '';
}
