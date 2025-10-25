{
  description = "My flake";

  inputs = {
    # ali-neovim.url = "git+file:///home/ali/git/neovim-nix-flake";
    # niri.url = "github:YaLTeR/niri";
    eks-creds.url = "github:alisonjenkins/eks-creds";
    flake-parts.url = "github:hercules-ci/flake-parts";
    impermanence.url = "github:nix-community/impermanence";
    jovian-nixos.url = "github:Jovian-Experiments/Jovian-NixOS";
    niri-flake.url = "github:sodiboo/niri-flake/27e012b4cd49e9ac438573ec7a6db3e5835828c3";
    nix-colors.url = "github:misterio77/nix-colors";
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    nixgl.url = "github:nix-community/nixGL";
    nixos-cosmic.url = "github:lilyinstarlight/nixos-cosmic";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixpkgs_master.url = "github:nixos/nixpkgs";
    nixpkgs_stable.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs_stable_darwin.url = "github:nixos/nixpkgs/nixpkgs-25.05-darwin";
    nixpkgs_unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixvirt.url = "github:AshleyYakeley/NixVirt/v0.6.0";
    stylix.url = "github:danth/stylix/release-25.05";

    ali-neovim = {
      url = "github:alisonjenkins/neovim-nix-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs_unstable";
        nixpkgs-master.follows = "nixpkgs_master";
        nixpkgs-stable.follows = "nixpkgs_stable";
      };
    };

    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";

      inputs = {
        nixpkgs.follows = "nixpkgs_unstable";
      };
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

    lsfg-vk-flake = {
      url = "github:pabloaul/lsfg-vk-flake/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixcord = {
      url = "github:kaylorben/nixcord/a8802dc23e112f98196a7daa68f0e246c7a0ea64";
    };

    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs = {
        nixpkgs.follows = "nixpkgs_unstable";
        quickshell.follows = "quickshell";
      };
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
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs_unstable";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";

      inputs = {
        nixpkgs.follows = "nixpkgs_unstable";
      };
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tmux-sessionizer = {
      url = "github:alisonjenkins/tmux-sessionizer/b9965259166c588479c01328e34f0fbc98fa03a2";
      inputs = {
        nixpkgs.follows = "nixpkgs_unstable";
      };
    };

    # umu = {
    #   url = "git+https://github.com/Open-Wine-Components/umu-launcher/?dir=packaging\/nix&submodules=1";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs =
    { self
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
            (import ./overlays { inherit inputs system lib; }).master-packages
            (import ./overlays { inherit inputs system lib; }).unstable-packages
            (import ./overlays { inherit inputs system lib; }).zk
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
    in
    {
      darwinConfigurations =
        let
          username = "ajenkins";
          system = "aarch64-darwin";

          pkgs = import inputs.nixpkgs_stable_darwin {
            inherit system;

            config = {
              allowUnfree = true;
            };

            overlays =
              [
                (import ./overlays { inherit inputs system lib; }).master-packages
                (import ./overlays { inherit inputs system lib; }).unstable-packages
                (import ./overlays { inherit inputs system lib; }).zk
                inputs.nur.overlays.default
                inputs.rust-overlay.overlays.default
                (self: super: {
                  nodejs = super.unstable.nodejs;
                })
              ];
          };

          commonArgs = {
            inherit inputs;
            inherit outputs;
            inherit pkgs;
            inherit system;
            inherit username;
          };

          hostnames = {
            civica = "Alisons-MacBook-Pro";
          };
        in
        {
          "${hostnames.civica}" = inputs.darwin.lib.darwinSystem {
            system = system;
            modules = [
              ./hosts/ali-work-laptop-macos/configuration.nix
              home-manager.darwinModules.home-manager
              {
                home-manager.backupFileExtension = ".bak";
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users.${username} = import ./home/home-macos.nix;
                home-manager.extraSpecialArgs = commonArgs // {
                  gitEmail = "alison.jenkins@civica.com";
                  gitGPGSigningKey = "~/.ssh/id_civica.pub";
                  gitUserName = "Alison Jenkins";
                  hostname = "${hostnames.civica}";
                  primarySSHKey = "~/.ssh/id_civica.pub";
                };
              }
            ];
            specialArgs = commonArgs // {
              hostname = "${hostnames.civica}";
            };
          };
        };

      homeConfigurations = {
        "ali" = inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            ./home/home-linux.nix
            ./hosts/ali-desktop-arch/configuration.nix
            # inputs.stylix.homeModules.stylix
          ];

          extraSpecialArgs = {
            inherit inputs;
            inherit system;
            username = "ali";
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
            ./home/home-linux.nix
            ./hosts/steam-deck/configuration.nix
            inputs.nix-index-database.homeModules.nix-index
          ];

          extraSpecialArgs = {
            gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            gitGPGSigningKey = "";
            gitUserName = "Alison Jenkins";
            inherit inputs;
            inherit system;
            primarySSHKey = "~/.ssh/id_personal.pub";
            username = "deck";
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
            # inputs.nixos-cosmic.nixosModules.default
            ./app-profiles/desktop/aws
            ./app-profiles/desktop/display-managers/greetd
            ./app-profiles/desktop/wms/hyprland
            ./app-profiles/desktop/wms/plasma6
            ./app-profiles/hardware/vr
            ./hosts/ali-desktop/configuration.nix
            inputs.niri-flake.nixosModules.niri
            inputs.nix-flatpak.nixosModules.nix-flatpak
            nur.modules.nixos.default
            sops-nix.nixosModules.sops
            home-manager.nixosModules.home-manager
            {
              home-manager.backupFileExtension = "bak";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${specialArgs.username} = import ./home/home-linux.nix;
              home-manager.extraSpecialArgs =
                specialArgs
                // {
                  bluetoothHeadsetMac = bluetoothMacs.sonyHeadset;
                  gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
                  gitGPGSigningKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
                  gitUserName = "Alison Jenkins";
                  primarySSHKey = "~/.ssh/id_personal.pub";
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
            ./app-profiles/desktop/display-managers/greetd-regreet
            ./app-profiles/desktop/local-k8s
            ./app-profiles/desktop/wms/hyprland
            ./app-profiles/desktop/wms/plasma6
            ./app-profiles/hardware/vr
            ./hosts/ali-framework-laptop/configuration.nix
            ./modules/development/web
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            inputs.niri-flake.nixosModules.niri
            inputs.nix-flatpak.nixosModules.nix-flatpak
            inputs.nixos-hardware.nixosModules.framework-16-7040-amd
            nur.modules.nixos.default
            sops-nix.nixosModules.sops
            {
              home-manager.backupFileExtension = ".bak";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${specialArgs.username} = import ./home/home-linux.nix;
              home-manager.extraSpecialArgs =
                specialArgs
                // {
                  # gitGPGSigningKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
                  bluetoothHeadsetMac = bluetoothMacs.sonyHeadset;
                  gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
                  gitGPGSigningKey = "";
                  gitUserName = "Alison Jenkins";
                  primarySSHKey = "~/.ssh/id_personal.pub";
                };
            }
          ];
        };

        ali-work-laptop = lib.nixosSystem rec {
          inherit system;
          specialArgs = {
            username = "ali";
            inherit inputs;
            inherit outputs;
            inherit system;
          };
          modules = [
            ./app-profiles/desktop/aws
            ./app-profiles/desktop/display-managers/greetd-regreet
            ./app-profiles/desktop/local-k8s
            ./app-profiles/desktop/wms/hyprland
            ./app-profiles/desktop/wms/plasma6
            ./hosts/ali-work-laptop/configuration.nix
            ./hosts/ali-work-laptop/disko-config.nix
            ./modules/development/web
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager
            inputs.niri-flake.nixosModules.niri
            inputs.nix-flatpak.nixosModules.nix-flatpak
            nur.modules.nixos.default
            sops-nix.nixosModules.sops
            {
              home-manager.backupFileExtension = ".bak";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${specialArgs.username} = import ./home/home-linux.nix;
              home-manager.extraSpecialArgs =
                specialArgs
                // {
                  bluetoothHeadsetMac = bluetoothMacs.sonyHeadset;
                  gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
                  gitGPGSigningKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
                  gitUserName = "Alison Jenkins";
                  primarySSHKey = "~/.ssh/id_civica.pub";
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
        #     inputs.jovian-nixos.nixosModules.default
        #     inputs.nix-flatpak.nixosModules.nix-flatpak
        #     inputs.stylix.nixosModules.stylix
        #     nur.modules.nixos.default
        #     sops-nix.nixosModules.sops
        #     home-manager.nixosModules.home-manager
        #     {
        #       home-manager.useGlobalPkgs = true;
        #       home-manager.useUserPackages = true;
        #       home-manager.users.${specialArgs.username} = import ./home/home-linux.nix;
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

        dev-vm =
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
              #   home-manager.users.ali = import ./home/home-linux.nix;
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

        download-server-1 = lib.nixosSystem rec {
          inherit system;
          specialArgs = {
            username = "ali";
            inherit inputs;
            inherit outputs;
            inherit system;
          };
          modules = [
            ./hosts/download-server-1/configuration.nix
            ./hosts/download-server-1/hardware-configuration.nix
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
          ];
        };


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
            #   home-manager.users.ali = import ./home/home-linux.nix;
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
            ./hosts/home-storage-server-1/configuration.nix
            ./hosts/home-storage-server-1/disko-config.nix
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            # home-manager.nixosModules.home-manager
            # {
            #   home-manager.useGlobalPkgs = true;
            #   home-manager.useUserPackages = true;
            #   home-manager.users.ali = import ./home/home-linux.nix;
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

      # nixOnDroidConfigurations = let
      #   pkgs = import nixpkgs {
      #     system = "aarch64-linux";
      #
      #     config = {
      #       allowUnfree = true;
      #     };
      #
      #     overlays = [
      #         (import ./overlays { inherit inputs system lib; }).master-packages
      #         (import ./overlays { inherit inputs system lib; }).unstable-packages
      #         inputs.nur.overlays.default
      #         inputs.rust-overlay.overlays.default
      #     ];
      #   };
      # in
      # {
      #   default = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
      #     pkgs = pkgs;
      #
      #     modules = [
      #       {
      #         environment = {
      #           systemPackages = with pkgs; [
      #             dua
      #             git
      #             inputs.ali-neovim.packages.${system}.nvim
      #             just
      #           ];
      #         };
      #       }
      #     ];
      #   };
      # };

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;

      deploy = {
        nodes = {
          ali-framework-laptop = {
            hostname = "ali-framework-laptop-wifi.lan";
            profiles = {
              system = {
                user = "root";
                path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.ali-framework-laptop;
              };
            };
          };

          ali-work-laptop = {
            hostname = "ali-work-laptop.lan";
            profiles = {
              system = {
                user = "root";
                path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.ali-work-laptop;
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

          download-server-1 = {
            hostname = "download-server-1.lan";
            profiles = {
              system = {
                user = "root";
                path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.download-server-1;
              };
            };
          };

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

      overlays = import ./overlays {
        inherit inputs;
        inherit system;
        inherit lib;
      };

      templates = {
        rust = {
          description = "A Rust flake template with Rust Overlay and devshell setup.";
          path = ./templates/rust;
        };
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
}
