{
  pkgs,
  ...
}:
{
  imports = [
    ./alacritty
    ./bat
    ./broot
    ./carapace
    ./comodoro
    ./gh
    ./gh-dash
    ./git
    ./granted
    ./hyfetch
    ./info
    ./k9s
    ./kitty
    ./lsd
    ./man
    ./mcfly
    ./newsboat
    ./nix-index
    ./noti
    ./nushell
    ./starship
    ./tmux
    ./yazi
    ./zsh
  ];
  # ++ (if pkgs.stdenv.isLinux then [
  #   # ./plasma5
  #   ./dunst
    # ./firefox
  #   ./hyprland
  #   ./mimetypes
    # ./obs
  #   ./rofi
  #   ./waybar
  # ] else []) ++ (if pkgs.stdenv.isDarwin then [
  # ] else []);
}
