{
  description = "My flake";

  inputs = {
    ali-neovim.url = "github:alisonjenkins/neovim-nix-flake";
    # ali-neovim.url = "git+file:///home/ali/git/neovim-nix-flake";
    nix-colors.url = "github:misterio77/nix-colors";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.1.0";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs_stable.url = "github:nixos/nixpkgs/nixos-23.11";
    nur.url = "github:nix-community/NUR";

    chaotic = {
      url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    jovian-nixos = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nh = {
      url = "github:viperML/nh";
      inputs.nixpkgs.follows = "nixpkgs"; # override this repo's nixpkgs snapshot
    };
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixpkgs_stable, home-manager, hyprland, disko, jovian-nixos, nix-colors, chaotic, nix-gaming, sops-nix, nur, ... }@inputs:

    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
    in
    {
      nixosConfigurations = {
        ali-desktop = lib.nixosSystem rec {
          inherit system;
          specialArgs =
            let
              gpgSigningKey = "B561E7F6";
            in
            {
              inherit hyprland;
              inherit inputs;
              inherit system;
              inherit gpgSigningKey;
            };
          modules = [
            ./app-profiles/desktop/display-managers/greetd
            ./app-profiles/desktop/wms/hypr
            ./app-profiles/desktop/wms/plasma5
            ./hosts/ali-desktop/configuration.nix
            chaotic.nixosModules.default
            hyprland.nixosModules.default
            inputs.nix-flatpak.nixosModules.nix-flatpak
            nur.nixosModules.nur
            sops-nix.nixosModules.sops
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
          specialArgs = let gpgSigningKey = "AD723B26"; in
            {
              inherit gpgSigningKey;
              inherit hyprland;
              inherit inputs;
              inherit system;
            };
          modules = [
            ./app-profiles/desktop/display-managers/greetd
            ./app-profiles/desktop/wms/hypr
            ./app-profiles/desktop/wms/plasma5
            ./hosts/ali-laptop/configuration.nix
            chaotic.nixosModules.default
            hyprland.nixosModules.default
            inputs.nix-flatpak.nixosModules.nix-flatpak
            nur.nixosModules.nur
            sops-nix.nixosModules.sops
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
          specialArgs = {
            inherit inputs;
            inherit system;
          };
          modules = [
            ./hosts/home-kvm-hypervisor-1/configuration.nix
            ./hosts/home-kvm-hypervisor-1/disko-config.nix
            disko.nixosModules.disko
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
          specialArgs = {
            inherit inputs;
            inherit system;
          };
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
          lib = nixpkgs.lib;

        in
        lib.nixosSystem rec {
          inherit system;
          specialArgs = { inherit hyprland; };
          modules = [
            ./hosts/dev-vm/configuration.nix
            disko.nixosModules.disko
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
