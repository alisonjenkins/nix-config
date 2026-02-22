{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  pkgs = import inputs.nixpkgs {
    inherit system;

    config = {
      allowUnfree = true;
    };

    overlays =
      let overlays = import ../../overlays { inherit inputs; };
      in [
        overlays.additions
        overlays.lqx-pin-packages
        overlays.master-packages
        overlays.unstable-packages
        overlays.zk
        overlays.qbittorrent
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
        ../../home/home-linux.nix
        ../../hosts/ali-desktop-arch/configuration.nix
      ];

      extraSpecialArgs = {
        inherit inputs system;
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
        ../../home/home-linux.nix
        ../../hosts/steam-deck/configuration.nix
        inputs.nix-index-database.homeModules.nix-index
      ];

      extraSpecialArgs = {
        gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
        gitGPGSigningKey = "";
        gitUserName = "Alison Jenkins";
        hostname = "steam-deck";
        inherit inputs system;
        primarySSHKey = "~/.ssh/id_personal.pub";
        username = "deck";
      };
    };
  };
}
