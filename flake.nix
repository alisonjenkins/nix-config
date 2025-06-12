{
  description = "My flake";

  inputs = {
    # ali-neovim.url = "git+file:///home/ali/git/neovim-nix-flake";
    ali-neovim.url = "github:alisonjenkins/neovim-nix-flake";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
    eks-creds.url = "github:alisonjenkins/eks-creds";
    impermanence.url = "github:nix-community/impermanence";
    jovian-nixos.url = "github:Jovian-Experiments/Jovian-NixOS";
    musnix = { url = "github:musnix/musnix"; };
    nix-colors.url = "github:misterio77/nix-colors";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.1.0";
    nixgl.url = "github:nix-community/nixGL";
    nixos-cosmic.url = "github:lilyinstarlight/nixos-cosmic";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixpkgs_master.url = "github:nixos/nixpkgs";
    nixpkgs_stable.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs_unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixvirt.url = "github:AshleyYakeley/NixVirt/v0.5.0";
    rust-overlay.url = "github:oxalica/rust-overlay";
    stylix.url = "github:danth/stylix/release-25.05";
    tmux-sessionizer.url = "github:jrmoulton/tmux-sessionizer";

    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nh = {
      url = "github:viperML/nh";
      inputs.nixpkgs.follows = "nixpkgs"; # override this repo's nixpkgs snapshot
    };

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/nur";
    };

    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-25.05";
      # url = "path:/home/ali/git/nixpkgs";
    };

    # nix-gaming = {
    #   url = "github:fufexan/nix-gaming";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix-rosetta-builder = {
    #   url = "github:cpick/nix-rosetta-builder";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    plasma-manager = {
      url = "github:pjones/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # umu = {
    #   url = "git+https://github.com/Open-Wine-Components/umu-launcher/?dir=packaging\/nix&submodules=1";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs =
    { self
    , chaotic
    , disko
    , home-manager
    , nixpkgs
    , nur
    , sops-nix
    , ...
    } @ inputs:
    let
      inherit (self) outputs;
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = import nixpkgs {
        inherit system;

        config = {
          allowUnfree = true;
        };

        overlays =
          [
            (import ./overlays { inherit inputs system pkgs lib; }).master-packages
            (import ./overlays { inherit inputs system pkgs lib; }).unstable-packages
            (import ./overlays { inherit inputs system pkgs lib; }).zk
            inputs.nur.overlays.default
            inputs.rust-overlay.overlays.default
          ]
          ++ (
            if builtins.getEnv "HOSTNAME" == "steamdeck"
            then [ inputs.nixgl.overlay ]
            else [ ]
          );
      };
    in
    {
      darwinConfigurations =
        let
          username = "ajenkins";
          system = "aarch64-darwin";
          hostname = "JVKLHFPJ65";
          specialArgs = {
            inherit hostname;
            inherit inputs;
            inherit outputs;
            inherit pkgs;
            inherit system;
            inherit username;
          };

          pkgs = import nixpkgs {
            inherit system;

            config = {
              allowUnfree = true;
            };

            overlays =
              [
                (import ./overlays { inherit inputs system pkgs lib; }).master-packages
                (import ./overlays { inherit inputs system pkgs lib; }).unstable-packages
                (import ./overlays { inherit inputs system pkgs lib; }).zk
                inputs.nur.overlays.default
                inputs.rust-overlay.overlays.default
                (self: super: {
                  nodejs = super.unstable.nodejs;
                })
              ];
          };
        in
        {
          "${hostname}" = inputs.darwin.lib.darwinSystem {
            system = system;
            modules = [
              ./hosts/ali-work-laptop-macos/configuration.nix
              home-manager.darwinModules.home-manager
              {
                home-manager.backupFileExtension = ".bak";
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users.${username} = import ./home/home.nix;
                home-manager.extraSpecialArgs = specialArgs // {
                  gitUserName = "Alison Jenkins";
                  gitEmail = "alison.jenkins@brambles.com";
                  gitGPGSigningKey = "~/.ssh/id_brambles.pub";
                };
              }
            ];
            specialArgs = specialArgs;
          };
        };

      homeConfigurations = {
        "deck" = inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            ./home/home.nix
            ./hosts/steam-deck/configuration.nix
            inputs.nix-index-database.hmModules.nix-index
          ];

          extraSpecialArgs = {
            inherit inputs;
            inherit system;
            username = "deck";
            gitUserName = "Alison Jenkins";
            gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            gitGPGSigningKey = "";
          };
        };
      };

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
            # ./app-profiles/desktop/wms/sway
            ./app-profiles/desktop/aws
            ./app-profiles/desktop/display-managers/greetd-regreet
            ./app-profiles/desktop/wms/hyprland
            ./app-profiles/desktop/wms/plasma6
            ./app-profiles/hardware/vr
            ./hosts/ali-desktop/configuration.nix
            inputs.nix-flatpak.nixosModules.nix-flatpak
            inputs.nixos-cosmic.nixosModules.default
            nur.modules.nixos.default
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager.backupFileExtension = ".bak";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${specialArgs.username} = import ./home/home.nix;
              home-manager.extraSpecialArgs =
                specialArgs
                // {
                  gitUserName = "Alison Jenkins";
                  gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
                  gitGPGSigningKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
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
            # ./app-profiles/desktop/display-managers/greetd
            # ./app-profiles/desktop/wms/sway
            ./app-profiles/desktop/aws
            ./app-profiles/desktop/display-managers/sddm
            ./app-profiles/desktop/wms/plasma6
            ./app-profiles/desktop/wms/hyprland
            ./app-profiles/desktop/local-k8s
            ./hosts/ali-laptop/configuration.nix
            chaotic.nixosModules.default
            inputs.nix-flatpak.nixosModules.nix-flatpak
            inputs.stylix.nixosModules.stylix
            nur.modules.nixos.default
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager.backupFileExtension = ".bak";
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

        ali-framework-laptop = lib.nixosSystem rec {
          inherit system;
          specialArgs = {
            username = "ali";
            inherit inputs;
            inherit outputs;
            inherit system;
          };
          modules = [
            ./app-profiles/desktop/aws
            ./app-profiles/desktop/display-managers/sddm
            ./app-profiles/desktop/local-k8s
            ./app-profiles/desktop/wms/hyprland
            ./app-profiles/desktop/wms/plasma6
            ./app-profiles/hardware/vr
            ./hosts/ali-framework-laptop/configuration.nix
            disko.nixosModules.disko
            inputs.lanzaboote.nixosModules.lanzaboote
            inputs.nix-flatpak.nixosModules.nix-flatpak
            inputs.nixos-cosmic.nixosModules.default
            inputs.nixos-hardware.nixosModules.framework-16-7040-amd
            nur.modules.nixos.default
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager.backupFileExtension = ".bak";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${specialArgs.username} = import ./home/home.nix;
              home-manager.extraSpecialArgs =
                specialArgs
                // {
                  gitUserName = "Alison Jenkins";
                  gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
                  gitGPGSigningKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
                };
            }
            {
              nix.settings = {
                substituters = [ "https://cosmic.cachix.org/" ];
                trusted-public-keys = [ "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE=" ];
              };
            }
          ];
        };

        ali-work-laptop = lib.nixosSystem rec {
          system = "aarch64-linux";
          specialArgs = {
            username = "ali";
            inherit inputs;
            inherit outputs;
            inherit system;
          };
          modules = [
            ./app-profiles/desktop/aws
            ./app-profiles/desktop/display-managers/sddm
            ./app-profiles/desktop/wms/plasma6
            ./app-profiles/desktop/wms/hyprland
            ./app-profiles/desktop/local-k8s
            ./hosts/ali-work-laptop/configuration.nix
            ./hosts/ali-work-laptop/disko-config.nix
            disko.nixosModules.disko
            inputs.nix-flatpak.nixosModules.nix-flatpak
            inputs.stylix.nixosModules.stylix
            nur.modules.nixos.default
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager.backupFileExtension = ".bak";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${specialArgs.username} = import ./home/home.nix;
              home-manager.extraSpecialArgs =
                specialArgs
                // {
                  gitUserName = "Alison Jenkins";
                  gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
                  gitGPGSigningKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
                };
            }
          ];
        };

        # aws-server-1 = nixpkgs.lib.nixosSystem {
        #   modules = [
        #     "${nixpkgs}/nixos/maintainers/scripts/ec2/amazon-image.nix"
        #     "${nixpkgs}/nixos/lib/make-disk-image.nix"
        #     {
        #       ec2.hvm = true;
        #       nixpkgs.hostPlatform = "aarch64-linux";
        #       services.nginx.enable = true;
        #
        #       environment = {
        #         systemPackages = [
        #         ];
        #       };
        #
        #       virtualisation = {
        #         diskSizeAutoSupported = false;
        #         diskSize = 4096;
        #         # memorySize = 4096;
        #
        #         amazon-init = {
        #           enable = true;
        #         };
        #       };
        #     }
        #   ];
        # };

        # ali-steam-deck = lib.nixosSystem rec {
        #   inherit system;
        #   specialArgs = {
        #     username = "ali";
        #     inherit inputs;
        #     inherit outputs;
        #     inherit system;
        #   };
        #   modules = [
        #     # ./app-profiles/desktop/display-managers/greetd
        #     # ./app-profiles/desktop/wms/sway
        #     ./app-profiles/desktop/aws
        #     ./app-profiles/desktop/wms/plasma6
        #     ./app-profiles/desktop/wms/hyprland
        #     ./app-profiles/desktop/local-k8s
        #     ./hosts/ali-steam-deck/configuration.nix
        #     chaotic.nixosModules.default
        #     inputs.jovian-nixos.nixosModules.default
        #     inputs.nix-flatpak.nixosModules.nix-flatpak
        #     inputs.stylix.nixosModules.stylix
        #     nur.modules.nixos.default
        #     sops-nix.nixosModules.sops
        #     home-manager.nixosModules.home-manager
        #     {
        #       home-manager.useGlobalPkgs = true;
        #       home-manager.useUserPackages = true;
        #       home-manager.users.${specialArgs.username} = import ./home/home.nix;
        #       home-manager.extraSpecialArgs =
        #         specialArgs
        #         // {
        #           gitUserName = "Alison Jenkins";
        #           gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
        #           gitGPGSigningKey = "";
        #           extraImports = [ ./home/wms/hyprland ];
        #         };
        #     }
        #   ];
        # };

        home-k8s-master-1 = lib.nixosSystem rec {
          inherit system;
          specialArgs = {
            username = "ali";
            inherit inputs;
            inherit outputs;
            inherit system;
          };
          modules = [
            ./hosts/home-k8s-master-1/configuration.nix
            ./hosts/home-k8s-master-1/hardware-configuration.nix
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
          ];
        };

        home-kvm-hypervisor-1 = lib.nixosSystem rec {
          inherit system;
          specialArgs = {
            username = "ali";
            inherit inputs;
            inherit outputs;
            inherit system;
          };
          modules = [
            ./hosts/home-kvm-hypervisor-1/configuration.nix
            ./hosts/home-kvm-hypervisor-1/disko-config.nix
            disko.nixosModules.disko
            inputs.nixvirt.nixosModules.default
            sops-nix.nixosModules.sops
            # home-manager.nixosModules.home-manager
            # {
            #   home-manager.useGlobalPkgs = true;
            #   home-manager.useUserPackages = true;
            #   home-manager.users.ali = import ./home/home.nix;
            #   home-manager.extraSpecialArgs =
            #     specialArgs
            #     // {
            #       gitUserName = "Alison Jenkins";
            #       gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            #       gitGPGSigningKey = "";
            #       extraImports = [ ./home/wms/hyprland ];
            #     };
            # }
          ];
        };

        home-storage-server-1 = lib.nixosSystem rec {
          inherit system;
          specialArgs = {
            username = "ali";
            inherit inputs;
            inherit outputs;
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
            #   home-manager.extraSpecialArgs =
            #     specialArgs
            #     // {
            #       gitUserName = "Alison Jenkins";
            #       gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            #       gitGPGSigningKey = "";
            #       extraImports = [ ./home/wms/hyprland ];
            #     };
            # }
          ];
        };

        home-k8s-server-1 = lib.nixosSystem rec {
          inherit system;
          specialArgs = {
            username = "ali";
            inherit inputs;
            inherit outputs;
            inherit system;
          };
          modules = [
            disko.nixosModules.disko
            ./hosts/home-k8s-server-1/disko-config.nix
            ./hosts/home-k8s-server-1/configuration.nix
          ];
        };
      };

      nixOnDroidConfigurations = let
        pkgs = import nixpkgs {
          system = "aarch64-linux";

          config = {
            allowUnfree = true;
          };

          overlays = [
              (import ./overlays { inherit inputs system pkgs lib; }).master-packages
              (import ./overlays { inherit inputs system pkgs lib; }).unstable-packages
              inputs.nur.overlays.default
              inputs.rust-overlay.overlays.default
          ];
        };
      in
      {
        default = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
          pkgs = pkgs;

          modules = [
            {
              environment = {
                systemPackages = with pkgs; [
                  dua
                  git
                  inputs.ali-neovim.packages.${system}.nvim
                  just
                ];
              };
            }
          ];
        };
      };

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;

      deploy = {
        nodes = {
          ali-laptop = {
            hostname = "ali-laptop-wifi.lan";
            profiles = {
              system = {
                user = "root";
                path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.ali-laptop;
              };
            };
          };
          ali-framework-laptop = {
            hostname = "ali-framework-laptop-wifi.lan";
            profiles = {
              system = {
                user = "root";
                path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.ali-framework-laptop;
              };
            };
          };
          # ali-steam-deck = {
          #   hostname = "aliju-steam-deck.lan";
          #   profiles = {
          #     system = {
          #       user = "root";
          #       path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.ali-steam-deck;
          #     };
          #   };
          # };
          home-kvm-hypervisor-1 = {
            hostname = "home-kvm-hypervisor-1.lan";
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
          home-k8s-master-1 = {
            hostname = "home-k8s-master-1.lan";
            profiles = {
              system = {
                user = "root";
                path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.home-k8s-master-1;
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

      nixosConfigurations."dev-vm" =
        let
          system = "aarch64-linux";
          lib = nixpkgs.lib;
        in
        lib.nixosSystem rec {
          inherit system;

          specialArgs = {
            username = "ali";
            inherit inputs;
            inherit outputs;
            inherit system;
          };

          modules = [
            ./hosts/dev-vm/configuration.nix
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            # home-manager.nixosModules.home-manager
            # {
            #   home-manager.useGlobalPkgs = true;
            #   home-manager.useUserPackages = true;
            #   home-manager.users.ali = import ./home/home.nix;
            #   home-manager.extraSpecialArgs =
            #     specialArgs
            #     // {
            #       gitUserName = "Alison Jenkins";
            #       gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            #       gitGPGSigningKey = "";
            #     };
            # }
          ];
        };

      overlays = import ./overlays {
        inherit inputs;
        inherit system;
        inherit pkgs;
        inherit lib;
      };

      devShells =
        let
          buildInputs = with pkgs; [
            deploy-rs
            just
            libsecret
            nix-fast-build
            nixos-anywhere
          ];
        in
        {
          x86_64-linux.default = pkgs.mkShell {
            buildInputs = buildInputs;
          };
          aarch64-darwin.default =
            let
              pkgs = import inputs.nixpkgs {
                system = "aarch64-darwin";
                config = {
                  allowUnfree = true;
                };
              };
            in
            pkgs.mkShell {
              buildInputs = buildInputs;
            };
        };
    };

  nixConfig = {
    sandbox = true;
    experimental-features = [
      "flakes"
      "nix-command"
    ];
    extra-platforms = [
      "aarch64-linux"
      "x86_64-linux"
      "i686-linux"
    ];
    builders = "@local";
  };
}
