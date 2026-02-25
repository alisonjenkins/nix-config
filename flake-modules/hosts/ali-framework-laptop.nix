{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
  bluetoothMacs = {
    sonyHeadset = "88:C9:E8:06:5E:9C";
  };
in {
  flake.nixosConfigurations.ali-framework-laptop = lib.nixosSystem rec {
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
      ../../app-profiles/hardware/vr
      ../../hosts/ali-framework-laptop/configuration.nix
      ../../modules/audio-context-suspend.nix
      ../../modules/development/web
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      inputs.niri-flake.nixosModules.niri
      inputs.nix-flatpak.nixosModules.nix-flatpak
      inputs.nixos-hardware.nixosModules.framework-16-7040-amd
      inputs.nur.modules.nixos.default
      inputs.sops-nix.nixosModules.sops
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
        home-manager.users.${specialArgs.username} = {
          imports = [
            (import ../../home/home-linux.nix)
            inputs.framework-inputmodule-rs-flake.homeManagerModules.default
            {
              services.inputmodule-control = {
                enable = true;
                package = inputs.framework-inputmodule-rs-flake.packages.x86_64-linux.inputmodule-control;

                ledMatrix.both = {
                  brightness = 5;
                  clock = true;
                  waitForDevice = true;
                };
              };
            }
          ];
        };
        home-manager.extraSpecialArgs =
          specialArgs
          // {
            hostname = "ali-framework-laptop";
            bluetoothHeadsetMac = bluetoothMacs.sonyHeadset;
            gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            gitGPGSigningKey = "";
            gitUserName = "Alison Jenkins";
            github_clone_ssh_host_personal = "github.com";
            github_clone_ssh_host_work = "github.com";
            primarySSHKey = "~/.ssh/id_personal.pub";
          };
      }
    ];
  };
}
