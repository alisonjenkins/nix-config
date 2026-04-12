{ ... }: {
  flake.homeModules = {
    home-common = import ../home/home-common.nix;
    home-linux = import ../home/home-linux.nix;
    home-macos = import ../home/home-macos.nix;
    programs = import ../home/programs;
    programs-linux-only = import ../home/programs/linux-only;
    programs-macos-only = import ../home/programs/macos-only;
    scripts = import ../home/scripts;
    themes = import ../home/themes;
    autostart = import ../home/autostart;
    wm-river = import ../home/wms/river;

    # Host-specific home-manager configs
    ali-desktop-arch-config = { pkgs, ... }: {
      nix = {
        package = pkgs.nix;
        settings = {
          trusted-users = [ "root" "@wheel" ];
          experimental-features = "nix-command flakes";
        };
      };
    };
    steam-deck-config = { pkgs, ... }: {
      nix = {
        package = pkgs.nix;
        settings = {
          trusted-users = [ "root" "@wheel" ];
        };
      };
    };
  };
}
