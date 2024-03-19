{ lib, hyprland, pkgs, nix-colors, inputs, username, ... }: rec {

  # imports = [
  #   hyprland.homeManagerModules.default
  #   inputs.plasma-manager.homeManagerModules.plasma-manager
  #   ./programs
  #   ./scripts
  #   ./themes
  # ];

  isMac=lib.version.platform.system=="darwin";

  home = {
    username = username;
    homeDirectory = (lib.mkIf isMac "/Users/${username}" "/home/${username}");
  };

  home.packages = (if isMac then [] else (with pkgs; [
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
  ]));
  #
  # programs.home-manager.enable = true;
  # targets.genericLinux.enable = true;
  #
  # services = (lib.mkIf isMac {} {
  #   ssh-agent.enable = true;
  #   gpg-agent = {
  #     enable = true;
  #     pinentryPackage = pkgs.kwalletcli;
  #     enableBashIntegration = true;
  #     enableZshIntegration = true;
  #     extraConfig = "pinentry-program ${pkgs.kwalletcli}/bin/pinentry-kwallet";
  #   };
  # });

  home.stateVersion = "23.11";
}
