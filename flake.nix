{
  description = "My flake";

  inputs = {
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    disko = { url = "github:nix-community/disko"; inputs.nixpkgs.follows = "nixpkgs"; };
    home-manager = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    hyprland.url = "github:hyprwm/Hyprland";
    jovian-nixos = { url = "github:Jovian-Experiments/Jovian-NixOS"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-colors.url = "github:misterio77/nix-colors";
    nix-gaming.url = "github:fufexan/nix-gaming";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = { nixpkgs, home-manager, hyprland, disko, jovian-nixos, nix-colors, chaotic, nix-gaming, sops-nix, ... }@inputs:

    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      lib = nixpkgs.lib;
    in
    {
      nixosConfigurations = {
        ali-desktop = lib.nixosSystem rec {
          inherit system;
          specialArgs = {
            inherit hyprland; inherit inputs;
          };
          modules = [
            ./hosts/ali-desktop/configuration.nix
            ./app-profiles/desktop/display-managers/greetd
            ./app-profiles/desktop/wms/plasma5
            ./app-profiles/desktop/wms/hypr
            sops-nix.nixosModules.sops
            chaotic.nixosModules.default
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
          inherit system;
          specialArgs = { inherit hyprland; inherit nix-colors; };
          modules = [
            ./hosts/ali-laptop/configuration.nix
            ./app-profiles/desktop/display-managers/greetd
            ./app-profiles/desktop/wms/plasma5
            ./app-profiles/desktop/wms/hypr
            sops-nix.nixosModules.sops
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

        ali-steamdeck = lib.nixosSystem rec {
          inherit system;
          specialArgs = { inherit jovian-nixos; };

          modules = [
            ./hosts/ali-steamdeck/configuration.nix
          ];
        };

        home-kvm-hypervisor-1 = lib.nixosSystem rec {
          inherit system;
          # specialArgs = {};
          modules = [
            disko.nixosModules.disko
            ./hosts/home-kvm-hypervisor-1/disko-config.nix
            ./hosts/home-kvm-hypervisor-1/configuration.nix
            sops-nix.nixosModules.sops
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
          inherit system;
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
      nixosConfigurations."dev-vm" =
        let
          system = "aarch64-linux";
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          lib = nixpkgs.lib;

        in
        lib.nixosSystem rec {
          inherit system;
          specialArgs = { inherit hyprland; };
          modules = [
            disko.nixosModules.disko
            ./hosts/dev-vm/configuration.nix
            sops-nix.nixosModules.sops
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
}
