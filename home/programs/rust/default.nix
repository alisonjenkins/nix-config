{
  pkgs,
  username,
  ...
}: {
  home.packages =
    if pkgs.stdenv.isLinux && username == "deck"
    then
      with pkgs; [
        rust-bin.stable.latest.default
      ]
    else [];
}
