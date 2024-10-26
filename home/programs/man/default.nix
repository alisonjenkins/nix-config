{ pkgs, ... }: {
  programs.man = {
    enable = (
      if pkgs.system == "x86_64-linux"
      then true
      else false
    );
    generateCaches = (
      if pkgs.system == "x86_64-linux"
      then true
      else false
    );
  };
}
