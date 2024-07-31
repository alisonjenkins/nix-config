{
  description = "My flake";

  inputs = {
    # ali-neovim.url = "git+file:///home/ali/git/neovim-nix-flake";
    ali-neovim.url = "github:alisonjenkins/neovim-nix-flake";
    deploy-rs.url = "github:serokell/deploy-rs";
    impermanence.url = "github:nix-community/impermanence";
    musnix = {url = "github:musnix/musnix";};
    nix-colors.url = "github:misterio77/nix-colors";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.1.0";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs_master.url = "github:nixos/nixpkgs";
    nixpkgs_stable.url = "github:nixos/nixpkgs/nixos-24.05";
    nur.url = "github:nix-community/NUR";
    rust-overlay.url = "github:oxalica/rust-overlay";
    tmux-sessionx.url = "github:omerxx/tmux-sessionx";

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
    ghostty = {
      url = "git+ssh://git@github.com/ghostty-org/ghostty";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
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
    home-manager,
    jovian-nixos,
    nix-colors,
    nix-gaming,
    nixpkgs,
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
        specialArgs = {
          username = "ali";
          inherit inputs;
          inherit outputs;
          inherit system;
        };
        modules = [
          # ./app-profiles/desktop/display-managers/sddm
          ./app-profiles/desktop/aws
          ./app-profiles/desktop/display-managers/greetd
          ./app-profiles/desktop/wms/plasma6
          ./app-profiles/desktop/wms/sway
          ./app-profiles/hardware/vr
          ./hosts/ali-desktop/configuration.nix
          ./hosts/ali-desktop/disko-config.nix
          chaotic.nixosModules.default
          inputs.impermanence.nixosModules.impermanence
          inputs.musnix.nixosModules.musnix
          inputs.nix-flatpak.nixosModules.nix-flatpak
          nur.nixosModules.nur
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            environment.systemPackages = [
              inputs.ghostty.packages.x86_64-linux.default
            ];
          }
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${specialArgs.username} = import ./home/home.nix;
            home-manager.extraSpecialArgs =
              specialArgs
              // {
                gitUserName = "Alison Jenkins";
                gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
                gitGPGSigningKey = "B561E7F6";
              };
          }
        ];
      };

      ali-laptop = lib.nixosSystem rec {
        inherit system;
        specialArgs = {
          username = "ali";
          inherit inputs;
          inherit outputs;
          inherit system;
        };
        modules = [
          ./app-profiles/desktop/display-managers/sddm
          # ./app-profiles/desktop/display-managers/greetd
          ./app-profiles/desktop/wms/plasma6
          ./app-profiles/desktop/wms/sway
          ./hosts/ali-laptop/configuration.nix
          chaotic.nixosModules.default
          inputs.nix-flatpak.nixosModules.nix-flatpak
          nur.nixosModules.nur
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            environment.systemPackages = [
              inputs.ghostty.packages.x86_64-linux.default
            ];
          }
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${specialArgs.username} = import ./home/home.nix;
            home-manager.extraSpecialArgs =
              specialArgs
              // {
                gitUserName = "Alison Jenkins";
                gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
                gitGPGSigningKey = "AD723B26";
              };
          }
        ];
      };

      # ali-steamdeck = lib.nixosSystem rec {
      #   inherit system;
      #   specialArgs = { inherit jovian-nixos; };
      #
      #   modules = [ ./hosts/ali-steamdeck/configuration.nix ];
      # };

      home-kvm-hypervisor-1 = lib.nixosSystem rec {
        inherit system;
        specialArgs = {
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

      home-k8s-server-1 = lib.nixosSystem rec {
        inherit system;
        specialArgs = {
          inherit inputs;
          inherit system;
        };
        modules = [
          disko.nixosModules.disko
          ./hosts/home-k8s-server-1/disko-config.nix
          ./hosts/home-k8s-server-1/configuration.nix
        ];
      };
    };

    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;

    deploy = {
      nodes = {
        home-kvm-hypervisor-1 = {
          hostname = "home-kvm-hypervisor.lan";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.home-kvm-hypervisor-1;
            };
          };
        };
        home-storage-server-1 = {
          hostname = "home-storage-server-1.lan";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.home-storage-server-1;
            };
          };
        };
        home-k8s-server-1 = {
          hostname = "home-k8s-server-1.lan";
          profiles = {
            system = {
              user = "root";
              path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.home-k8s-server-1;
            };
          };
        };
      };
    };

    nixosConfigurations."dev-vm" = let
      system = "aarch64-linux";
      lib = nixpkgs.lib;
    in
      lib.nixosSystem {
        inherit system;
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

    overlays = import ./overlays {
      inherit inputs;
      inherit system;
    };
  };
}
