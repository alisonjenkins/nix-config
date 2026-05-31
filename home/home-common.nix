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

  # Azure DevOps only supports RSA keys (not ed25519); work machines override
  # this via extraSpecialArgs, personal machines get the empty-string default.
  _module.args.azureDevopsRsaKey = lib.mkDefault "";

  _module.args.enableDifftastic = lib.mkDefault true;

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
    # ssh-agent disabled in favour of 1Password's SSH agent (see
    # modules.desktop-1password). Running both fights over SSH_AUTH_SOCK.
    ssh-agent.enable = false;

    gpg-agent = {
      enable = lib.mkIf pkgs.stdenv.isLinux true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      # kwalletcli was removed in nixpkgs 26.05 (Plasma 5 EOL) with no Qt6
      # drop-in. The previous override forced mainProgram = pinentry-qt
      # anyway, so use the Qt pinentry directly (no KWallet passphrase
      # caching; plain Qt dialog).
      pinentry.package = pkgs.pinentry-qt;
    };
  };

  # HM 26.05 tracks upstream master while nixpkgs is 25.11 stable — expected mismatch
  home.enableNixpkgsReleaseCheck = false;

  home.stateVersion = "24.05";
}
