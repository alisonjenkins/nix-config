{ pkgs
, username
, ...
}: {
  home.packages =
    if pkgs.stdenv.isLinux && username == "deck"
    then
      with pkgs; [
        gcc
      ]
    else [ ];
}
