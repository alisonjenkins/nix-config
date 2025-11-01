{ pkgs
, inputs
, lib
, username
, ...
}: {
  imports = [
    ./autostart
    ./programs
    ./scripts
    ./themes
    ./wms/hyprland
    ./wms/river
    inputs.plasma-manager.homeModules.plasma-manager
    inputs.nix-index-database.homeModules.nix-index
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

  home.sessionVariables = import ./environmentVariables.nix { inherit pkgs; };
  home.shellAliases = import ./shellAliases.nix { inherit pkgs; };

  home.packages =
    if pkgs.stdenv.isLinux
    then
      (with pkgs;
      [
        # cava
        # mission-center
        # neovide
        appimage-run
        audacity
        aws-vault
        awscli2
        bc
        bibata-cursors
        btop
        cachix
        cargo-cross
        cargo-nextest
        catimg
        curl
        dipc
        direnv
        dive
        eog
        eza
        freeplane
        git
        gnumake
        grim
        just
        kubecm
        kubectl
        kubectx
        kubernetes-helm
        kustomize
        mpc-cli
        networkmanagerapplet
        nurl
        pamixer
        pavucontrol
        prismlauncher
        qpwgraph
        screen
        slurp
        ssm-session-manager-plugin
        teams-for-linux
        tig
        tty-clock
        unstable.fluxcd
        # vesktop
        webcord
        wget
        wl-clipboard
        wlr-randr
        xflux
        zenity
        zola
        zoxide
      ]
      ++ (
        if pkgs.system == "x86_64-linux"
        then [
          # inputs.umu.packages.${pkgs.system}.umu
          unstable.lutris
          unigine-heaven
        ]
        else [ ]
      ))
    else [ ];

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
      enableBashIntegration = true;
      enableZshIntegration = true;
      extraConfig = "pinentry-program ${pkgs.kwalletcli}/bin/pinentry-kwallet";
      pinentry.package = pkgs.kwalletcli.overrideAttrs (_: prev: {
        meta =
          prev.meta
          // {
            mainProgram = "pinentry-qt";
          };
      });
    };
  };

  home.stateVersion = "24.05";
}
