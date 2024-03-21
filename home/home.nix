{
  hyprland,
  pkgs,
  nix-colors,
  inputs,
  ...
}: {
  imports = [
    hyprland.homeManagerModules.default
    inputs.plasma-manager.homeManagerModules.plasma-manager
    ./programs
    ./scripts
    ./themes
  ];

  home = {
    username = "ali";
    homeDirectory = "/home/ali";
  };

  home.packages =
    (with pkgs; [
      appimage-run
      audacity
      bibata-cursors
      btop
      catimg
      cava
      curl
      direnv
      # discord
      dunst
      eza
      git
      gnumake
      grim
      lollypop
      lutris
      mcfly
      mission-center
      mpc-cli
      neovide
      networkmanagerapplet
      nitch
      openrgb
      pamixer
      pavucontrol
      qpwgraph
      slurp
      starship
      tty-clock
      wget
      wl-clipboard
      wlr-randr
      xflux
      zoxide
    ])
    ++ (with pkgs.gnome; [
      zenity
      eog
    ]);

  programs.home-manager.enable = true;
  targets.genericLinux.enable = true;

  services = {
    ssh-agent.enable = true;
    gpg-agent = {
      enable = true;
      pinentryPackage = pkgs.kwalletcli;
      enableBashIntegration = true;
      enableZshIntegration = true;
      extraConfig = "pinentry-program ${pkgs.kwalletcli}/bin/pinentry-kwallet";
    };
  };

  home.stateVersion = "23.11";
}
