{
  description = "My flake";

  inputs = {
    # ali-neovim.url = "git+file:///home/ali/git/neovim-nix-flake";
    ali-neovim.url = "github:alisonjenkins/neovim-nix-flake";
    attic.url = "github:zhaofengli/attic";
    ecrrepos.url = "git+ssh://git@github.com/Synalogik/various-maintenance-scripts?dir=ecrrepos";
    impermanence.url = "github:nix-community/impermanence";
    maven.url = "github:nixos/nixpkgs/15e3765c4e5ec347935e737f57c1b20874f2de69";
    nix-colors.url = "github:misterio77/nix-colors";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.1.0";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs_master.url = "github:nixos/nixpkgs";
    nixpkgs_stable.url = "github:nixos/nixpkgs/nixos-23.11";
    nur.url = "github:nix-community/NUR";
    rust-overlay.url = "github:oxalica/rust-overlay";

    chaotic = {
      url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin";
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
    plasma-manager = {
      url = "github:pjones/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    chaotic,
    darwin,
    disko,
    fenix,
    home-manager,
    hyprland,
    jovian-nixos,
    nix-colors,
    nix-gaming,
    nixpkgs,
    nixpkgs_master,
    nixpkgs_stable,
    nur,
    rust-overlay,
    plasma-manager,
    sops-nix,
    ...
  } @ inputs: let
    inherit (self) outputs;
    system = "x86_64-linux";
    lib = nixpkgs.lib;
  in {
    nixosConfigurations = {
      ali-desktop = lib.nixosSystem rec {
        inherit system;
        specialArgs = let
          gpgSigningKey = "B561E7F6";
        in {
          inherit gpgSigningKey;
          inherit hyprland;
          inherit inputs;
          inherit outputs;
          inherit system;
        };
        modules = [
          ./app-profiles/desktop/display-managers/greetd
          # ./app-profiles/desktop/display-managers/sddm
          ./app-profiles/desktop/aws
          ./app-profiles/desktop/wms/hypr
          ./app-profiles/desktop/wms/plasma6
          ./hosts/ali-desktop/configuration.nix
          chaotic.nixosModules.default
          hyprland.nixosModules.default
          inputs.nix-flatpak.nixosModules.nix-flatpak
          inputs.impermanence.nixosModules.impermanence
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
        specialArgs = let
          gpgSigningKey = "AD723B26";
        in {
          inherit gpgSigningKey;
          inherit hyprland;
          inherit inputs;
          inherit outputs;
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
        specialArgs = {inherit jovian-nixos;};

        modules = [./hosts/ali-steamdeck/configuration.nix];
      };

      home-kvm-hypervisor-1 = lib.nixosSystem rec {
        inherit system;
        specialArgs = {
          inherit hyprland;
          inherit inputs;
          inherit outputs;
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

    darwinConfigurations."Alison-SYNALOGIK-MBP-20W1M" = let
      system = "aarch64-darwin";
      specialArgs = {
        inherit inputs;
        inherit outputs;
        inherit system;
        username = "ajenkins";
      };
      gitSpecialArgs = {
        gitUserName = "Alison Jenkins";
        gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
        gitGPGSigningKey = "37F33EF6";
      };
    in
      darwin.lib.darwinSystem {
        modules = [
          ./hosts/darwin/configuration.nix
          ({pkgs, ...}: {
            nixpkgs.overlays = [rust-overlay.overlays.default];
          })
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${specialArgs.username} = import ./home/home.nix;
            home-manager.extraSpecialArgs = specialArgs // gitSpecialArgs;
          }
        ];
        specialArgs = specialArgs;
      };

    nixosConfigurations."dev-vm" = let
      system = "aarch64-linux";
      lib = nixpkgs.lib;
    in
      lib.nixosSystem {
        inherit system;
        specialArgs = {inherit hyprland;};
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

    overlays = import ./overlays {inherit inputs;};
  };
}
