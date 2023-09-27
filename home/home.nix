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
    discord
    dunst
    eza
    git
    gnumake
    grim
    lollypop
    lutris
    mpc-cli
    neovide
    neovim
    nitch
    openrgb
    pamixer
    pavucontrol
    qpwgraph
    rofi
    slurp
    rtx
    tty-clock
    wget
    wl-clipboard
    wlr-randr
    xflux
  ]) ++ (with pkgs.gnome; [
    zenity
    eog
  ]);

  programs.home-manager.enable = true;

  home.stateVersion = "23.05";
}
