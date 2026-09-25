{ pkgs, inputs, lib, ... }:
let
  # noctalia 5.x is a from-scratch C++/OpenGL-ES rewrite — the old quickshell
  # QML tree (share/noctalia-shell/**.qml) no longer exists, so the previous
  # substituteInPlace patches (perf-mode blur/spectrum disable + lid-switch
  # inhibit) have no targets. 5.x also dropped the custom "noctaliaPerformanceMode"
  # visual flag entirely. Use the package vanilla; configure blur/idle via toml.
  noctalia-shell = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [
    ./module.nix
    inputs.noctalia.homeModules.default
  ];

  home.packages = if pkgs.stdenv.isLinux then with pkgs; [
    fuzzel
    inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
    nautilus
    unstable.wlr-which-key
    wlsunset
    # unstable: 0.8.1 panics with "Failed flushing clientside events:
    # Io(BrokenPipe)" (src/server/mod.rs:882) whenever the DP-2 connector
    # disconnects — monitor sleep or session lock. The panic takes DISPLAY=:0
    # down with it, so every X11 client (Steam, Discord, Keybase, ZapZap) dies
    # silently, no core and no crash log. Observed 8 times in the week to
    # 2026-08-14. 0.8.2 is the newest release; upstream tracks this class of
    # flush panic in Supreeeme/xwayland-satellite#210 and niri-wm/niri#2159.
    #
    # Patched: X saw every output mode change one change late, because the
    # xdg-output LogicalSize handler forwards the size stored from the last
    # wl_output.mode, which arrives after it (PENDING.md item 11). The patch
    # adds a regression test, so the unit tests are run: nixpkgs skips them.
    (unstable.xwayland-satellite.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../../../../patches/xwayland-satellite-logical-size-on-mode.patch ];
      doCheck = true;
      cargoTestFlags = [ "--lib" ];
    }))
  ] else [];

  # Run noctalia as a systemd user service (Restart=on-failure) bound to
  # graphical-session.target, instead of a fire-once niri spawn-at-startup.
  # spawn-at-startup never respawns, so a single transient exit (e.g. the
  # one-off dbus-broker disconnect seen 2026-06-24T06:09Z) killed the shell
  # permanently. As a service it self-heals in ~1s and stderr lands in the
  # journal (journalctl --user -u noctalia) for future diagnosis. The module
  # adds noctalia-shell to home.packages itself. settings left unset so the
  # user's mutable ~/.config/noctalia is untouched.
  #
  # mkDefault: home/programs/linux-only is imported by every Linux home
  # config, so hosts that run a different desktop (e.g. ali-steam-deck, which
  # is Gaming Mode + Plasma) can switch the niri shell off in
  # home/machines/<hostname> without the shell autostarting into their
  # session via graphical-session.target.
  programs.noctalia = {
    enable = lib.mkDefault true;
    package = noctalia-shell;
    systemd.enable = true;
  };

  custom.niri.enable = lib.mkDefault true;

  home.file.".config/wlr-which-key/config.yaml".source = ./wlr-which-key/config.yaml;
}
