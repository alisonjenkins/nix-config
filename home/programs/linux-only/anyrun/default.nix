{pkgs, ...}: {
  home.packages = with pkgs; [
    unstable.anyrun
  ];
  home.file = {
    ".config/anyrun/config.ron".text = (import ./config.ron.nix);
  };
}
