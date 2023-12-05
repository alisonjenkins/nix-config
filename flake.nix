{
  description = "My flake";

  inputs = {
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland.url = "github:hyprwm/Hyprland";
  };

  outputs = { self, nixpkgs, home-manager, hyprland, disko, ... }:

    let
      # system = "x86_64-linux";
      pkgs = import nixpkgs {
        # inherit system;
        config.allowUnfree = true;
      };
      lib = nixpkgs.lib;
    in
    {
      nixosConfigurations = {
        ali-desktop = lib.nixosSystem rec {
          # inherit system;
          specialArgs = { inherit hyprland; };
          modules = [
            ./hosts/ali-desktop/configuration.nix
            ./app-profiles/desktop/display-managers/greetd
            ./app-profiles/desktop/wms/plasma5
            ./app-profiles/desktop/wms/hypr
            hyprland.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ali = import ./home/home.nix;
              home-manager.extraSpecialArgs = specialArgs;
            }
          ];
        };

        ali-laptop = lib.nixosSystem rec {
          # inherit system;
          specialArgs = { inherit hyprland; };
          modules = [
            ./hosts/ali-laptop/configuration.nix
            ./app-profiles/desktop/display-managers/greetd
            ./app-profiles/desktop/wms/plasma5
            ./app-profiles/desktop/wms/hypr
            hyprland.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ali = import ./home/home.nix;
              home-manager.extraSpecialArgs = specialArgs;
            }
          ];
        };

        dev-vm = lib.nixosSystem rec {
          # inherit system;
          specialArgs = { inherit hyprland; };
          modules = [
            disko.nixosModules.disko
            ./hosts/dev-vm/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.ali = import ./home/home.nix;
              home-manager.extraSpecialArgs = specialArgs;
            }
          ];
        };

        home-kvm-hypervisor-1 = lib.nixosSystem rec {
          # inherit system;
          # specialArgs = {};
          modules = [
            disko.nixosModules.disko
            ./hosts/home-kvm-hypervisor-1/disko-config.nix
            ./hosts/home-kvm-hypervisor-1/configuration.nix
            # home-manager.nixosModules.home-manager
            # {
            #   home-manager.useGlobalPkgs = true;
            #   home-manager.useUserPackages = true;
            #   home-manager.users.ali = import ./home/home.nix;
            #   home-manager.extraSpecialArgs = specialArgs;
            # }
          ];
        };
        home-storage-server-1 = lib.nixosSystem rec {
          # inherit system;
          # specialArgs = {};
          modules = [
            disko.nixosModules.disko
            ./hosts/home-storage-server-1/disko-config.nix
            ./hosts/home-storage-server-1/configuration.nix
            # home-manager.nixosModules.home-manager
            # {
            #   home-manager.useGlobalPkgs = true;
            #   home-manager.useUserPackages = true;
            #   home-manager.users.ali = import ./home/home.nix;
            #   home-manager.extraSpecialArgs = specialArgs;
            # }
          ];
        };
      };
    };
}
