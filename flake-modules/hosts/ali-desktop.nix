{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
  bluetoothMacs = {
    sonyHeadset = "88:C9:E8:06:5E:9C";
  };
in {
  flake.nixosConfigurations.ali-desktop = lib.nixosSystem rec {
    inherit system;
    specialArgs = {
      username = "ali";
      inherit inputs outputs system;
    };
    modules = [
      # ../app-profiles/desktop/wms/sway
      # inputs.nixos-cosmic.nixosModules.default
      ../../app-profiles/desktop/aws
      ../../app-profiles/desktop/display-managers/greetd-regreet
      ../../app-profiles/desktop/wms/hyprland
      ../../app-profiles/desktop/wms/plasma6
      ../../app-profiles/hardware/vr
      ../../hosts/ali-desktop/configuration.nix
      ../../modules/audio-context-suspend.nix
      inputs.niri-flake.nixosModules.niri
      inputs.nix-flatpak.nixosModules.nix-flatpak
      inputs.nur.modules.nixos.default
      inputs.sops-nix.nixosModules.sops
      inputs.home-manager.nixosModules.home-manager
      {
        nixpkgs.overlays = [
          self.overlays.qbittorrent
        ];

        # Use timestamp-based backups to prevent conflicts
        home-manager.backupCommand = ''
          mv -v "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
        '';
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.${specialArgs.username} = import ../../home/home-linux.nix;
        home-manager.extraSpecialArgs =
          specialArgs
          // {
            hostname = "ali-desktop";
            bluetoothHeadsetMac = bluetoothMacs.sonyHeadset;
            gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            gitGPGSigningKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
            gitUserName = "Alison Jenkins";
            github_clone_ssh_host_personal = "github.com";
            github_clone_ssh_host_work = "github.com";
            primarySSHKey = "~/.ssh/id_personal.pub";
          };
      }
    ];
  };
}
