{pkgs, ...}: {
  home.packages =
    if pkgs.stdenv.isLinux
    then
      with pkgs; [
        _1password
        _1password-gui
      ]
    else [];
}
