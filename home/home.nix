{ hyprland, pkgs, ... }: {

  imports = [
    hyprland.homeManagerModules.default
    ./programs
    ./scripts
    ./themes
  ];

  home = {
    username = "ali";
    homeDirectory = "/home/ali";
  };

  home.packages = (with pkgs; [
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
    neovim
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
  ]) ++ (with pkgs.gnome; [
    zenity
    eog
  ]);

  programs.home-manager.enable = true;
  targets.genericLinux.enable = true;

  home.stateVersion = "23.11";
}
