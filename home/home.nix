{ hyprland, pkgs, nix-colors, ... }: {

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

  home.sessionVariables = {
    GDK_BACKEND = "wayland,x11";
    QT_QPA_PLATFORM = "wayland;xcb";
    #SDL_VIDEODRIVER = "x11";
    CLUTTER_BACKEND = "wayland";
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    XDG_SESSION_DESKTOP = "Hyprland";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  programs.home-manager.enable = true;
  targets.genericLinux.enable = true;

  services = {
    ssh-agent.enable = true;
    gpg-agent = {
      enable = true;
      pinentryFlavor = "qt";
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
  };

  home.stateVersion = "23.11";
}
