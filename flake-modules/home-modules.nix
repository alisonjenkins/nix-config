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
    vr = import ../home/modules/vr;
    wm-river = import ../home/wms/river;

    # Host-specific home-manager configs
    ali-desktop-arch-config = { pkgs, ... }: {
      nix = {
        package = pkgs.nix;
        settings = {
          trusted-users = [ "root" "@wheel" ];
          experimental-features = "nix-command flakes";
        };
        # Periodic GC via a systemd user timer running nix-collect-garbage.
        # Note: on this multi-user nix install a *user* config can't set
        # daemon-level min-free/max-free or auto-optimise-store, so this is
        # periodic GC only (no free-space-triggered GC / store optimise).
        gc = {
          automatic = true;
          frequency = "weekly";
          options = "--delete-older-than 60d";
        };
      };
    };
    steam-deck-config = { pkgs, ... }: {
      nix = {
        package = pkgs.nix;
        settings = {
          trusted-users = [ "root" "@wheel" ];
        };
        # Periodic GC via a systemd user timer (see ali-desktop-arch-config
        # for the multi-user-daemon caveat).
        gc = {
          automatic = true;
          frequency = "weekly";
          options = "--delete-older-than 60d";
        };
      };
    };
  };
}
