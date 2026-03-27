{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  pkgs = import inputs.nixpkgs {
    inherit system;

    config = {
      allowUnfree = true;
    };

    overlays = [
        self.overlays.additions
        self.overlays.lqx-pin-packages
        self.overlays.master-packages
        self.overlays.unstable-packages
        self.overlays.zk
        self.overlays.qbittorrent
        inputs.nur.overlays.default
        inputs.rust-overlay.overlays.default
      ]
      ++ (
        if builtins.getEnv "HOSTNAME" == "steamdeck"
        then [ inputs.nixgl.overlay ]
        else [ ]
      );
  };

  bluetoothMacs = {
    sonyHeadset = "88:C9:E8:06:5E:9C";
  };
in {
  flake.homeConfigurations = {
    "ali" = inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      modules = [
        self.homeModules.home-linux
        self.homeModules.ali-desktop-arch-config
      ];

      extraSpecialArgs = {
        inherit inputs;
        username = "ali";
        hostname = "ali-desktop-arch";
        bluetoothHeadsetMac = bluetoothMacs.sonyHeadset;
        gitUserName = "Alison Jenkins";
        gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
        primarySSHKey = "~/.ssh/id_personal.pub";
        gitGPGSigningKey = "";
      };
    };

    "deck" = inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      modules = [
        self.homeModules.home-linux
        self.homeModules.steam-deck-config
        inputs.nix-index-database.homeModules.nix-index
      ];

      extraSpecialArgs = {
        gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
        gitGPGSigningKey = "";
        gitUserName = "Alison Jenkins";
        hostname = "steam-deck";
        inherit inputs;
        primarySSHKey = "~/.ssh/id_personal.pub";
        username = "deck";
      };
    };
  };
}
