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
    xwayland-satellite
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
