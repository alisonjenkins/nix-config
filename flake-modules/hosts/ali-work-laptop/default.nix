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
    specialArgs = {
      username = "ali";
      inherit inputs outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }

      # Custom modules via flake outputs
      self.nixosModules.app-desktop
      self.nixosModules.app-desktop-aws
      self.nixosModules.app-desktop-greetd-regreet
      self.nixosModules.app-desktop-kde-connect
      self.nixosModules.app-desktop-kwallet
      self.nixosModules.app-desktop-local-k8s
      self.nixosModules.app-hardware-fingerprint-reader
      self.nixosModules.app-hardware-touchpad
      self.nixosModules.audio-context-suspend
      self.nixosModules.base
      self.nixosModules.desktop
      self.nixosModules.development-web
      self.nixosModules.libvirtd
      self.nixosModules.locale
      self.nixosModules.niks3-cache-push
      self.nixosModules.ollama
      self.nixosModules.plymouth
      self.nixosModules.podman
      self.nixosModules.ali-work-laptop-hardware
      self.nixosModules.ali-work-laptop-disko-config

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      inputs.nix-flatpak.nixosModules.nix-flatpak
      inputs.nur.modules.nixos.default
      inputs.sops-nix.nixosModules.sops

      # Home-manager configuration
      {
        # Use timestamp-based backups to prevent conflicts
        home-manager.backupCommand = ''
          mv -v "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
        '';
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.${specialArgs.username} = {
          imports = [ self.homeModules.home-linux ];

          # Sync mic mute LED with PipeWire state by also toggling the ALSA
          # Capture Switch, which drives the audio-micmute LED trigger.
          custom.niri.micMuteShellCommand = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle; if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED; then amixer -q -c 0 sset Capture nocap; else amixer -q -c 0 sset Capture cap; fi";
        };
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

      # Host-specific configuration
      ({ config, lib, inputs, outputs, pkgs, ... }: {
        modules.plymouth.enable = true;
        # TODO: Enable once secrets/niks3-token.enc.yaml is created with sops
        # modules.niks3CachePush = {
        #   enable = true;
        #   authTokenFile = config.sops.secrets.niks3-token.path;
        # };
        #
        # sops.secrets.niks3-token = {
        #   sopsFile = self + "/secrets/niks3-token.enc.yaml";
        #   key = "niks3_token";
        # };

        modules.base = {
          enable = true;
          enableImpermanence = true;
          enableCachyOSKernel = true;
          bootLoader = "secure-boot";
          pcr15Value = "2ed3e75741c65cda190d143376c463c88557e8d7ab53f8dfe788a263aaec50b7";
          suspendState = "mem";
          hibernateMode = "shutdown";
          timezone = null;  # Use automatic-timezoned for VPN-proof timezone detection
        };

        services.automatic-timezoned.enable = true;
        modules.locale.enable = true;
        modules.ollama.enable = true;
        modules.libvirtd.enable = true;
        modules.podman.enable = true;
        modules.podman.enableQemuBinfmt = true;

        modules.desktop = {
          enable = true;

          power = {
            hibernateDelaySec = "1h";  # Hibernate after 1 hour of suspend
            handleLidSwitch = "suspend-then-hibernate";
            handleLidSwitchExternalPower = "suspend-then-hibernate";
            handleLidSwitchDocked = "ignore";
            cleanWifiOnSuspend = true;
          };

          pipewire.quantum = 512;
        };

        services.audio-context-suspend = {
          enable = true;
          user = "ali";
          syncMicMuteLed = true;
        };

        # Override disko's keyFile (only used during initial install) so it doesn't
        # interfere with TPM2 auto-unlock in the initrd crypttab
        boot.initrd.luks.devices.crypted.keyFile = lib.mkForce null;

        boot = {
          kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-zen4;

          # Blacklist amd_pmf to prevent TEE errors after hibernate resume
          # The driver causes system instability with constant "TEE enact cmd failed" errors
          blacklistedKernelModules = [ "amd_pmf" ];

          extraModprobeConfig = ''
            options snd-hda-intel index=1,0
          '';

          kernelParams = [
            "amd_iommu=off"
            "amdgpu.runpm=0"  # Disable GPU runtime power management to prevent SMU race after suspend
          ];

        };

        console.keyMap = "us";

        environment = {
          pathsToLink = [ "/share/zsh" ];

          variables = {
            # NIXOS_OZONE_WL = "1";
            PATH = [
              "\${HOME}/.local/bin"
              "\${HOME}/.config/rofi/scripts"
            ];
            ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
          };

          systemPackages = with pkgs; [
            powershell
            sbctl
            slack
            # wallpapers # TODO: re-enable after wallpapers relocated from LFS
          ];
        };

        hardware = {
          graphics.enable = true;
        };

        networking = {
          hostName = "ali-work-laptop";
          networkmanager.enable = true;
        };

        nixpkgs = {
          overlays = [
            inputs.nur.overlays.default
            inputs.rust-overlay.overlays.default
            outputs.overlays._1password
            outputs.overlays.additions
            outputs.overlays.master-packages
            outputs.overlays.modifications
            outputs.overlays.stable-packages
            outputs.overlays.tmux-sessionizer
            outputs.overlays.unstable-packages
            outputs.overlays.linux-firmware
          ];
          config = {
            allowUnfree = true;
          };
        };

        programs = {
          niri = {
            enable = true;
            package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri;
          };
        };

        security.rtkit.enable = true;

        # Reduce ZRAM for faster hibernation (less data to serialize)
        zramSwap.memoryPercent = lib.mkForce 50;

        services = {
          pulseaudio = {
            enable = false;
          };

          pipewire = {
            enable = true;
            alsa.enable = true;
            alsa.support32Bit = true;
            pulse.enable = true;
          };

          power-profiles-daemon = {
            enable = lib.mkForce true;
          };

          tlp = {
            enable = lib.mkForce false;
          };

          thermald = {
            enable = true;
          };

          xserver = {
            videoDrivers = [ "amdgpu" ];
            xkb = {
              layout = "us";
              variant = "";
            };
          };
        };

        system = {
          stateVersion = "24.05";
        };

        users = {
          users = {
            ali = {
              isNormalUser = true;
              description = "Alison Jenkins";
              # initialPassword = "initPw!";
              hashedPasswordFile = "/persistence/passwords/ali";
              extraGroups = [ "networkmanager" "wheel" "docker" "realtime" ];

              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF"
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK2wZMFO69SYvoIIs6Atx/22PVy8wHtYy0MKpYtUMsez phone-ssh-key"
              ];
            };
          };
        };

        xdg.portal = {
          enable = true;
          xdgOpenUsePortal = true;
        };
      })
    ];
  };
}
