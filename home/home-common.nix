{ pkgs
, inputs
, lib
, username
, ...
}: {
  imports = [
    ./autostart
    ./modules/dedup.nix
    ./programs
    ./scripts
    ./themes
    inputs.nix-index-database.homeModules.nix-index
    inputs.plasma-manager.homeModules.plasma-manager
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
    [
      pkgs.nix-flake-template-init
    ]
    ++ (if pkgs.stdenv.isLinux
    then
      (with pkgs;
      [
        # cava
        # mission-center
        # neovide
        # unigine-heaven  # commented out due to hash mismatch
        # vesktop
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
        # eza
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
        mpc
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
        wget
        wl-clipboard
        wlr-randr
        zenity
        zola
        zoxide
      ]
      ++ (
        if pkgs.stdenv.hostPlatform.system == "x86_64-linux"
        then [
          # inputs.umu.packages.${pkgs.stdenv.hostPlatform.system}.umu
          unstable.lutris
        ]
        else [ ]
      ))
    else [ ]);

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
      pinentry.package = pkgs.kwalletcli.overrideAttrs (_: prev: {
        meta =
          prev.meta
          // {
            mainProgram = "pinentry-qt";
          };
      });
    };
  };

  # HM 26.05 tracks upstream master while nixpkgs is 25.11 stable — expected mismatch
  home.enableNixpkgsReleaseCheck = false;
  stylix.enableReleaseChecks = false;

  home.stateVersion = "24.05";
}
