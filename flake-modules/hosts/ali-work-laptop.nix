{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
  bluetoothMacs = {
    sonyHeadset = "88:C9:E8:06:5E:9C";
  };
in {
  flake.nixosConfigurations.ali-work-laptop = lib.nixosSystem rec {
    inherit system;
    specialArgs = {
      username = "ali";
      inherit inputs outputs system;
    };
    modules = [
      ../../app-profiles/desktop/aws
      ../../app-profiles/desktop/display-managers/greetd-regreet
      ../../app-profiles/desktop/local-k8s
      ../../app-profiles/desktop/wms/hyprland
      ../../app-profiles/desktop/wms/plasma6
      ../../hosts/ali-work-laptop/configuration.nix
      ../../hosts/ali-work-laptop/disko-config.nix
      ../../modules/audio-context-suspend.nix
      ../../modules/development/web
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      inputs.niri-flake.nixosModules.niri
      inputs.nix-flatpak.nixosModules.nix-flatpak
      inputs.nur.modules.nixos.default
      inputs.sops-nix.nixosModules.sops
      {
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
            hostname = "ali-work-laptop";
            bluetoothHeadsetMac = bluetoothMacs.sonyHeadset;
            gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            gitGPGSigningKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
            gitUserName = "Alison Jenkins";
            github_clone_ssh_host_personal = "pgithub.com";
            github_clone_ssh_host_work = "github.com";
            primarySSHKey = "~/.ssh/id_civica.pub";
          };
      }
    ];
  };
}
