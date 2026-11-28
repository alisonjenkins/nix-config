{ pkgs
, username
, ...
}: {
  home.packages =
    if pkgs.stdenv.hostPlatform.isLinux && username == "deck"
    then
      with pkgs; [
        gcc
      ]
    else [ ];
}
