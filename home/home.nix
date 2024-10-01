{
  pkgs,
  # nix-colors,
  inputs,
  lib,
  username,
  ...
}: {
  imports = [
    ./programs
    ./scripts
    ./themes
    inputs.plasma-manager.homeManagerModules.plasma-manager
  ];

  home = {
    inherit username;
    homeDirectory = lib.mkForce (
      if pkgs.stdenv.isDarwin
      then "/Users/${username}"
      else "/home/${username}"
    );
  };

  fonts = {
    fontconfig.enable = pkgs.stdenv.isLinux;
  };

  home.shellAliases = import ./shellAliases.nix;

  home.packages =
    if pkgs.stdenv.isLinux
    then
      (with pkgs; [
        appimage-run
        audacity
        aws-vault
        awscli2
        bc
        bibata-cursors
        btop
        cargo-nextest
        catimg
        cava
        curl
        dipc
        direnv
        dive
        eza
        fluxcd
        git
        gnumake
        grim
        kubectl
        kubernetes-helm
        kustomize
        lutris
        mission-center
        mpc-cli
        neovide
        networkmanagerapplet
        nurl
        openrgb
        pamixer
        pavucontrol
        pkgs.eog
        pkgs.zenity
        qpwgraph
        screen
        slurp
        ssm-session-manager-plugin
        teams-for-linux
        tig
        tty-clock
        wget
        wl-clipboard
        wlr-randr
        xflux
        zola
        zoxide
      ])
    else [];

  home.sessionVariables = {
    ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
  };

  programs.home-manager.enable =
    if pkgs.stdenv.isLinux
    then true
    else false;
  targets.genericLinux.enable =
    if pkgs.stdenv.isLinux
    then true
    else false;

  services = {
    ssh-agent.enable = lib.mkIf pkgs.stdenv.isLinux true;
    gpg-agent = {
      enable = lib.mkIf pkgs.stdenv.isLinux true;
      pinentryPackage = pkgs.kwalletcli.overrideAttrs (_: prev: {
        meta =
          prev.meta
          // {
            mainProgram = "pinentry-qt";
          };
      });
      enableBashIntegration = true;
      enableZshIntegration = true;
      extraConfig = "pinentry-program ${pkgs.kwalletcli}/bin/pinentry-kwallet";
    };
  };

  home.stateVersion = "23.11";
}
