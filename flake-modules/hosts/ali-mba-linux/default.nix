{ inputs, self, ... }:
let
  system = "aarch64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
in {
  flake.nixosConfigurations.ali-mba-linux = lib.nixosSystem rec {
    specialArgs = {
      username = "ali";
      inherit inputs outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }

      # Custom modules via flake outputs
      self.nixosModules.ali-mba-linux-hardware
      self.nixosModules.desktop-1password
      self.nixosModules.desktop-aws-tools
      self.nixosModules.desktop-base
      self.nixosModules.desktop-gaming-arm64
      self.nixosModules.desktop-greetd-regreet
      self.nixosModules.desktop-kde-connect
      self.nixosModules.desktop-kubernetes
      self.nixosModules.desktop-kwallet
      self.nixosModules.desktop-local-k8s
      self.nixosModules.desktop-media
      self.nixosModules.hardware-touchpad
      self.nixosModules.base
      self.nixosModules.desktop
      self.nixosModules.development-web
      self.nixosModules.libvirtd
      self.nixosModules.nohang
      self.nixosModules.uresourced
      self.nixosModules.locale
      self.nixosModules.podman
      self.nixosModules.power-management

      # External flake modules
      inputs.home-manager.nixosModules.home-manager
      inputs.nix-flatpak.nixosModules.nix-flatpak
      inputs.nixos-apple-silicon.nixosModules.default
      inputs.nur.modules.nixos.default
      inputs.sops-nix.nixosModules.sops

      # Home-manager configuration
      {
        home-manager.backupCommand = ''
          mv -v "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
        '';
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.${specialArgs.username} = {
          imports = [ self.homeModules.home-linux ];
          custom.niri.touchpadTap = false;
        };
        home-manager.extraSpecialArgs =
          specialArgs
          // {
            hostname = "ali-mba-linux";
            bluetoothHeadsetMac = "";  # No paired headset yet; swayidle uses empty string as no-op
            gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            gitGPGSigningKey = "";
            gitUserName = "Alison Jenkins";
            github_clone_ssh_host_personal = "github.com";
            github_clone_ssh_host_work = "github.com";
            primarySSHKey = "~/.ssh/id_personal.pub";
          };
      }

      # Host-specific configuration
      ({ config, lib, inputs, outputs, pkgs, ... }: {
        modules.desktop-1password.enable = true;
        modules.desktop-aws-tools.enable = true;
        modules.desktop-base.enable = true;
        modules.desktop-gaming-arm64.enable = true;
        modules.desktop-greetd-regreet.enable = true;
        modules.desktop-kde-connect.enable = true;
        modules.desktop-kubernetes.enable = true;
        modules.desktop-kwallet.enable = true;
        modules.desktop-local-k8s.enable = true;
        modules.desktop-media.enable = true;
        modules.hardware-touchpad.enable = true;
        modules.nohang = {
          enable = true;
          enableDesktopNotifications = true;
        };
        modules.uresourced.enable = true;

        modules.base = {
          enable = true;
          # Impermanence is intentionally OFF for first install. After the
          # plain ext4 root boots successfully, flip this to true and
          # switch the fileSystems block in hardware-configuration.nix to
          # the tmpfs + /nix + bind /persistence variant, then rebuild.
          enableImpermanence = false;
          # Apple Silicon boot chain is m1n1 -> u-boot -> systemd-boot.
          # Lanzaboote/secure-boot is x86 TPM-only and incompatible.
          bootLoader = "systemd-boot";
          # x86-only kernel overlay.
          enableCachyOSKernel = false;
          # Asahi S3 suspend is work-in-progress upstream; let auto-detect.
          suspendState = null;
          hibernateMode = "shutdown";
          timezone = null;  # Use automatic-timezoned for VPN-proof timezone detection
        };

        services.automatic-timezoned.enable = true;
        modules.locale.enable = true;
        modules.libvirtd.enable = true;
        modules.podman.enable = true;
        modules.podman.enableQemuBinfmt = false;  # Native aarch64; FEX handles x86 via desktop-gaming-arm64

        # Asahi NixOS module — kernel, m1n1+u-boot, GPU, audio, firmware.
        # GPU driver options (useExperimentalGPUDriver / experimentalGPUInstallMode /
        # withRust) were removed upstream once asahi support landed in mainline
        # mesa, so we just enable the module and let it pick the right kernel.
        #
        # Firmware: Apple peripheral firmware (Wi-Fi, etc) is non-redistributable.
        # Stored on the host at /var/lib/asahi-firmware (populated manually post
        # asahi-installer per docs/uefi-standalone.md). The value here is a
        # *string*, not a nix path literal — string assignments to `types.path`
        # options skip flake pure-eval's "absolute path is forbidden" check.
        # asahi-fwextract reads from this path at build time; the nix-daemon
        # sandbox is granted read access via `nix.settings.extra-sandbox-paths`
        # further down in this host config. Result: fully flake-pure (no
        # `--impure`), no files in the repo.
        hardware.asahi = {
          extractPeripheralFirmware = true;
          peripheralFirmwareDirectory = "/var/lib/asahi-firmware";
        };

        # Grant the nix-daemon build sandbox read access to the host firmware
        # dir so the asahi-fwextract derivation can read it. Without this,
        # builds error with "no such file or directory" or sandbox EACCES.
        nix.settings.extra-sandbox-paths = [ "/var/lib/asahi-firmware" ];

        # The asahi EFI is touched by m1n1/u-boot, not by NixOS. Touching
        # EFI variables from Linux on Apple Silicon does nothing useful
        # and produces warnings.
        boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

        # memtest86+ and netbootxyz are x86-only packages; the base
        # module enables them for systemd-boot unconditionally. Disable
        # here so aarch64 evaluation doesn't fail on missing platforms.
        boot.loader.systemd-boot.memtest86.enable = lib.mkForce false;
        boot.loader.systemd-boot.netbootxyz.enable = lib.mkForce false;

        # scx schedulers are x86-only (sched_ext + BPF helpers). The
        # desktop module enables scx by default; explicitly disable on
        # aarch64 so its package doesn't pull in.
        services.scx.enable = lib.mkForce false;

        modules.desktop = {
          enable = true;
          # x86-only gaming stack (Steam, ntsync, gpuVendor=amd/nvidia/intel
          # assumptions). Gaming on aarch64 lives in
          # modules.desktop-gaming-arm64 instead.
          gaming.enable = false;
          power = {
            hibernateDelaySec = "1h";
            handleLidSwitch = "suspend-then-hibernate";
            handleLidSwitchExternalPower = "suspend-then-hibernate";
            handleLidSwitchDocked = "ignore";
          };
          pipewire.quantum = 512;
        };

        modules.powerManagement = {
          enable = true;
          displayUser = "ali";
          noctaliaUser = "ali";
          onBattery = {
            ppdProfile = "power-saver";
            scxArgs = [ ];
            wifiPowerSave = true;
            pciRuntimePM = true;
            usbAutosuspend = true;
          };
          onAC = {
            ppdProfile = "balanced";
            scxArgs = [ ];
          };
        };

        console.keyMap = "us";

        environment = {
          pathsToLink = [ "/share/zsh" ];
        };

        hardware = {
          enableRedistributableFirmware = true;
          graphics = {
            enable = true;
            # enable32Bit is x86-only in NixOS; FEX-translated 32-bit
            # games rely on the FEX RootFS for the 32-bit stack, not
            # NixOS's i686 multilib path.
          };
          bluetooth = {
            enable = true;
            powerOnBoot = true;
          };
        };

        networking = {
          hostName = "ali-mba-linux";
          networkmanager = {
            enable = true;
            # iwd handles WPA3 on Broadcom Wi-Fi chips (Macs use Broadcom);
            # wpa_supplicant does not. Recommended by upstream asahi docs.
            wifi.backend = "iwd";
          };
          wireless.iwd.enable = true;
        };

        nix.package = pkgs.nix;

        nixpkgs = {
          overlays = [
            inputs.nur.overlays.default
            inputs.nixos-apple-silicon.overlays.default
            outputs.overlays.additions
            outputs.overlays.master-packages
            outputs.overlays.modifications
            outputs.overlays.stable-packages
            outputs.overlays.tmux-sessionizer
          ];
          config = {
            allowUnfree = true;
            # aarch64-linux nixpkgs flags some upstream packages as
            # broken (e.g. jellycli on aarch64). The desktop module's
            # systemPackages still includes them — allow eval to
            # proceed; broken packages simply won't be installed.
            allowBroken = true;
          };
        };

        programs = {
          niri = {
            enable = true;
            package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri;
          };
        };

        security.rtkit.enable = true;

        services = {
          pulseaudio.enable = false;
          pipewire = {
            enable = true;
            alsa.enable = true;
            alsa.support32Bit = true;
            pulse.enable = true;
          };
          power-profiles-daemon.enable = lib.mkForce true;
          tlp.enable = lib.mkForce false;
        };

        sops = {
          defaultSopsFile = self + "/secrets/main.enc.yaml";
          defaultSopsFormat = "yaml";
          age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
        };

        # Trust the remote builders' SSH host keys system-wide so
        # nix-daemon can ssh to them on first contact without prompting.
        programs.ssh.knownHosts = {
          ali-desktop-ts = {
            hostNames = [ "100.127.142.30" "ali-desktop.tail476348.ts.net" ];
            publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBHrvu44pLrT+P5uAD27syxuqJ/bWSvqydW+OwKluqlY";
          };
          home-k8s-master-1-ts = {
            hostNames = [ "100.87.232.102" "home-k8s-master-1.tail476348.ts.net" ];
            publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFMc6oarT75C2IAHHZQZLdJmBSjiHRQWZnj6UKvkPpCA";
          };
        };

        zramSwap.memoryPercent = lib.mkForce 50;

        system = {
          stateVersion = "25.11";
        };

        users = {
          users = {
            ali = {
              isNormalUser = true;
              description = "Alison Jenkins";
              extraGroups = [ "audio" "gamemode" "libvirt" "libvirtd" "networkmanager" "video" "wheel" "realtime" ];
              # Plain password during initial bring-up; switch to
              # hashedPasswordFile = "/persistence/passwords/ali"
              # when impermanence is enabled in pass 2.
              initialPassword = "changeme";
              openssh.authorizedKeys.keys = outputs.lib.sshKeys.all;
            };
            root = {
              initialPassword = "changeme";
            };
          };
        };

        xdg.portal = {
          enable = true;
          xdgOpenUsePortal = true;
          extraPortals = with pkgs; [
            xdg-desktop-portal-wlr
            xdg-desktop-portal-gtk
          ];
        };
      })
    ];
  };
}
