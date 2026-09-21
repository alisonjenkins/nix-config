{ ... }: {
  xdg.mimeApps.defaultApplications = {
    "text/plain" = [ "neovide.desktop" ];
    "applications/pdf" = [ "zathura.desktop" ];
    "image/*" = [ "sxiv.desktop" ];
    "video/png" = [ "mpv.desktop" ];
    "video/jpg" = [ "mpv.desktop" ];
    "video/*" = [ "mpv.desktop" ];
  };
  # NOTE: xdg.mimeApps.enable is deliberately never set here. Turning it on
  # makes home-manager own $XDG_CONFIG_HOME/mimeapps.list as a read-only
  # symlink, which on a live desktop is worse than it sounds: several apps
  # (Thunderbird's mailto handler, Discord's per-server PWA shortcuts) write
  # their own [Added Associations] entries into this file at runtime with
  # machine-generated ids, and a read-only file permanently stops any of
  # them from ever registering a new one again -- not just today's entries.
  # The defaultApplications above is therefore currently a no-op; it's kept
  # as the intended declarative surface for anyone who later decides the
  # tradeoff above is worth it and flips enable on.
}
