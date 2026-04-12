{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in {
  flake.nixosConfigurations.ali-steam-deck = lib.nixosSystem rec {
    specialArgs = {
      username = "ali";
      inherit inputs outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }

      # Custom modules via flake outputs
      self.nixosModules.ali-steam-deck-disko-config
      self.nixosModules.ali-steam-deck-hardware
      self.nixosModules.desktop-1password
      self.nixosModules.desktop-aws-tools
      self.nixosModules.desktop-base
      self.nixosModules.desktop-kubernetes
      self.nixosModules.desktop-media
      self.nixosModules.base
      self.nixosModules.desktop
      self.nixosModules.locale

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      inputs.jovian-nixos.nixosModules.default
      inputs.nix-flatpak.nixosModules.nix-flatpak
      inputs.nur.modules.nixos.default

      # Home-manager configuration
      {
        home-manager.backupCommand = ''
          mv -v "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
        '';
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.${specialArgs.username} = {
          imports = [ self.homeModules.home-linux ];
        };
        home-manager.extraSpecialArgs =
          specialArgs
          // {
            hostname = "ali-steam-deck";
            bluetoothHeadsetMac = "";
            gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            gitGPGSigningKey = "";
            gitUserName = "Alison Jenkins";
            github_clone_ssh_host_personal = "github.com";
            github_clone_ssh_host_work = "github.com";
            primarySSHKey = "~/.ssh/id_personal.pub";
          };
      }

      # Host-specific configuration
      ({ lib, pkgs, username, ... }: {
        modules.base = {
          enable = true;
          bootLoader = "grub";
          enableImpermanence = true;
          impermanencePersistencePath = "/persistence";
          enableCachyOSKernel = false;
          beesdFilesystems = {
            crypted = {
              spec = "LABEL=crypted";
              hashTableSizeMB = 256;
              verbosity = "crit";
              extraOptions = [ "--loadavg-target" "5.0" ];
            };
          };
        };

        modules.desktop.enable = true;
        modules.desktop-1password.enable = true;
        modules.desktop-aws-tools.enable = true;
        modules.desktop-base.enable = true;
        modules.desktop-kubernetes.enable = true;
        modules.desktop-media.enable = true;
        modules.locale.enable = true;

        boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
        boot.loader.grub.efiInstallAsRemovable = lib.mkForce true;

        # Let Jovian's custom Jupiter mesa override the desktop module's unstable mesa
        hardware.graphics.package = lib.mkForce pkgs.mesa;
        hardware.graphics.package32 = lib.mkForce pkgs.pkgsi686Linux.mesa;

        # Disable desktop-base's gamescope wrapper — Jovian provides its own
        programs.gamescope.enable = lib.mkForce false;

        # Resolve conflict: Jovian sets true, base module sets 1 (same meaning)
        boot.kernel.sysctl."net.ipv4.tcp_mtu_probing" = lib.mkForce 1;

        # Jovian manages the power button via its own daemon (powerbuttond)
        services.logind.settings.Login.HandlePowerKey = lib.mkForce "ignore";


        environment = {
          pathsToLink = [ "/share/zsh" ];

          variables = {
            PATH = [
              "\${HOME}/.local/bin"
              "\${HOME}/.config/rofi/scripts"
            ];
            ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
          };
        };

        jovian = {
          devices.steamdeck.enable = true;
          decky-loader.enable = true;

          steam = {
            enable = true;
            autoStart = true;
            user = username;
            desktopSession = "plasma";
          };
        };

        networking = {
          hostName = "ali-steam-deck";
          extraHosts = ''
            192.168.1.202 home-kvm-hypervisor-1
          '';
        };

        programs.steam = {
          remotePlay.openFirewall = true;
          dedicatedServer.openFirewall = true;
        };

        services.btrfs.autoScrub = {
          enable = true;
          fileSystems = [ "/persistence" ];
        };

        services.desktopManager.plasma6.enable = true;

        # Stylix theme is configured by the desktop module (gruvbox-dark-medium).

        system.stateVersion = "24.05";

        users.users.ali = {
          isNormalUser = true;
          description = "Alison Jenkins";
          initialPassword = "initPw!";
          extraGroups = [ "networkmanager" "wheel" "docker" "realtime" ];
          openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF" ];
          packages = with pkgs; [
            firefox
            fastfetch
          ];
        };

        xdg.portal = {
          enable = true;
          xdgOpenUsePortal = true;
        };

        # Desktop-only specialisation: boots directly into Plasma instead of
        # Gaming Mode. Selectable from GRUB at boot. Useful as a recovery
        # option when Steam's state is broken and Gaming Mode won't start.
        specialisation.desktop-mode.configuration = {
          jovian.steam.autoStart = lib.mkForce false;

          services.greetd = {
            enable = true;
            settings.default_session = {
              command = "${pkgs.kdePackages.plasma-workspace}/libexec/plasma-dbus-run-session-if-needed ${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland";
              user = username;
            };
          };

          system.nixos.tags = [ "desktop-mode" ];
        };
      })
    ];
  };
}
