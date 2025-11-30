{ pkgs, ... }: {
  programs.man = {
    enable = (
      if pkgs.stdenv.hostPlatform.system == "x86_64-linux"
      then true
      else false
    );
    generateCaches = (
      if pkgs.stdenv.hostPlatform.system == "x86_64-linux"
      then true
      else false
    );
  };
}
