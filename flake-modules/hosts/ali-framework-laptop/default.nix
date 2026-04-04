{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
  bluetoothMacs = {
    sonyHeadset = "88:C9:E8:06:5E:9C";
  };
in {
  flake.nixosConfigurations.ali-framework-laptop = lib.nixosSystem rec {
    specialArgs = {
      username = "ali";
      inherit inputs outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }

      # Custom modules via flake outputs
      self.nixosModules.ali-framework-laptop-disko-config
      self.nixosModules.ali-framework-laptop-hardware
      self.nixosModules.app-desktop
      self.nixosModules.app-desktop-aws
      self.nixosModules.app-desktop-greetd-regreet
      self.nixosModules.app-desktop-kde-connect
      self.nixosModules.app-desktop-kwallet
      self.nixosModules.app-desktop-local-k8s
      self.nixosModules.app-hardware-fingerprint-reader
      self.nixosModules.app-hardware-touchpad
      self.nixosModules.app-hardware-vr
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
      self.nixosModules.power-management
      self.nixosModules.rocm
      self.nixosModules.tts
      self.nixosModules.vr

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      inputs.nix-flatpak.nixosModules.nix-flatpak
      inputs.nixos-hardware.nixosModules.framework-16-7040-amd
      inputs.nur.modules.nixos.default
      inputs.sops-nix.nixosModules.sops

      # Home-manager configuration
      {
        nixpkgs.overlays = [
          self.overlays._1password
          self.overlays.qbittorrent
        ];

        # Use timestamp-based backups to prevent conflicts
        home-manager.backupCommand = ''
          mv -v "$1" "$1.backup-$(date +%Y%m%d-%H%M%S)"
        '';
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.${specialArgs.username} = {
          imports = [
            self.homeModules.home-linux
            inputs.framework-inputmodule-rs-flake.homeManagerModules.default
            {
              services.inputmodule-control = {
                enable = true;
                package = inputs.framework-inputmodule-rs-flake.packages.${system}.inputmodule-control;

                ledMatrix.both = {
                  brightness = 5;
                  clock = true;
                  waitForDevice = true;
                };
              };
            }
          ];

          programs.wluma = {
            enable = true;
            alsDevicePath = "/sys/bus/iio/devices";
            backlightPath = "/sys/class/backlight/amdgpu_bl2";
            outputName = "eDP-2";
          };
        };
        home-manager.extraSpecialArgs =
          specialArgs
          // {
            hostname = "ali-framework-laptop";
            bluetoothHeadsetMac = bluetoothMacs.sonyHeadset;
            gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            gitGPGSigningKey = "";
            gitUserName = "Alison Jenkins";
            github_clone_ssh_host_personal = "github.com";
            github_clone_ssh_host_work = "github.com";
            primarySSHKey = "~/.ssh/id_personal.pub";
          };
      }

      # Host-specific configuration (inlined from configuration.nix)
      ({ config, lib, inputs, outputs, pkgs, ... }: {
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

        modules.plymouth.enable = true;
        modules.base = {
          enable = true;
          enableImpermanence = true;
          bootLoader = "secure-boot";
          pcr15Value = "b538ad748a4d175bd234bf369e138b225bd9cfd55d6345763733578cd29700de";
          enableCachyOSKernel = true;
          hibernateMode = "shutdown";
          suspendState = "mem";
          timezone = null;  # Use automatic-timezoned for VPN-proof timezone detection
        };

        services.automatic-timezoned.enable = true;
        modules.locale.enable = true;
        modules.libvirtd.enable = true;
        modules.podman.enable = true;
        modules.podman.enableQemuBinfmt = true;
        modules.rocm.enable = true;
        modules.vr = {
          enable = true;
          enableOpenSourceVR = true;
          codec = "av1";
          bitrate = 30000000;
          scale = 0.7;
          encoders = [
            {
              encoder = "vaapi";
              codec = "av1";
              width = 1.0;
              height = 0.5;
              offset_x = 0.0;
              offset_y = 0.0;
            }
            {
              encoder = "vaapi";
              codec = "av1";
              width = 1.0;
              height = 0.5;
              offset_x = 0.0;
              offset_y = 0.5;
            }
          ];
        };
        modules.ollama.enable = true;
        modules.tts.enable = true;

        modules.powerManagement = {
          enable = true;
          onBattery = {
            ppdProfile = "power-saver";
            scxArgs = [ ];
            wifiPowerSave = true;
            pciRuntimePM = true;
            usbAutosuspend = true;
            dirtyWritebackCentisecs = 6000;
            noctaliaPerformanceMode = true;
            throttleFossilize = true;
            stopLact = true;
            bluetoothAutosuspend = true;
            displayMode = "2560x1600@60.000";
            enableVrr = true;
            kbdBacklightOff = "0012";
          };
          onAC = {
            ppdProfile = "balanced";
            scxArgs = [ "--performance" ];
            dirtyWritebackCentisecs = 500;
            displayMode = "2560x1600@165.000";
          };
          displayOutput = "eDP-2";
          displayUser = "ali";
          noctaliaUser = "ali";
        };

        modules.desktop = {
          enable = true;

          power = {
            hibernateDelaySec = "1h";  # Hibernate after 1 hour of suspend
            handleLidSwitch = "suspend-then-hibernate";
            handleLidSwitchExternalPower = "suspend-then-hibernate";
            handleLidSwitchDocked = "suspend-then-hibernate";
          };

          pipewire = {
            # Aggressive low-latency configuration with per-device overrides
            allowedSampleRates = [ 44100 48000 ];  # 48kHz for stable Bluetooth

            # Default quantum - will be overridden per device type by WirePlumber rules:
            # - ALSA (wired): uses minQuantum (256) for ~5.33ms latency
            # - Bluetooth: uses quantum (512) for ~10.67ms latency and stability
            quantum = 512;          # Default for Bluetooth and fallback
            minQuantum = 256;       # Aggressive low-latency for wired ALSA devices
            maxQuantum = 1024;      # Safety limit to prevent excessive buffering/desync

            # Alternative configs:
            # For even lower latency on wired (may cause crackling on some hardware):
            #   minQuantum = 128;  # ~2.67ms latency
            # For 96kHz support (adds latency, may cause video desync):
            #   allowedSampleRates = [ 44100 48000 96000 ];
            #   quantum = 1024;
            #   maxQuantum = 2048;

            resampleQuality = 10;   # soxr-hq (high quality resampling)
            suspendTimeoutSeconds = 0;  # Disable suspend-on-idle to prevent crackling
            alsaHeadroom = 2048;    # Increased headroom to prevent audio clipping/crackling
          };

          wifi = {
            optimizeForLowLatency = true;  # Enable low-latency WiFi for gaming/Discord/media
            roamThreshold = -70;           # Aggressive roaming on 2.4GHz (-70 dBm)
            roamThreshold5G = -72;         # Aggressive roaming on 5GHz (-72 dBm)
            bandModifier5GHz = 1.3;        # Prefer 5GHz band (30% bonus)
            bandModifier6GHz = 1.5;        # Strongly prefer 6GHz if available (50% bonus)
          };

          bluetooth = {
            optimizeForLowLatency = true;  # Enable low-latency Bluetooth for gaming/Discord/media
            enableFastConnectable = true;  # Faster connections (higher power use)
            reconnectAttempts = 7;         # Number of reconnection attempts
            reconnectIntervals = [ 1 2 4 8 16 32 64 ];  # Exponential backoff for reconnects
            audioCodecPriority = [ "ldac" "aptx_hd" "aptx" "aac" "sbc_xq" "sbc" ];  # Prefer high-quality codecs
            ldacQuality = "sq";            # Standard Quality LDAC (660 kbps, balanced quality/latency)
            defaultSampleRate = 48000;     # 48 kHz sample rate
          };

          gaming = {
            gpuVendor = "amd";
            cpuTopology = "8:16";  # Framework 16 with Ryzen 7 7840HS: 8 cores, 16 threads
            enableDxvkStateCache = true;
            enableVkd3dShaderCache = true;
            dxvkHud = "0";  # Disable HUD for performance
            enableLargeAddressAware = true;
            shaderCacheBasePath = "/media/storage/shader-cache";  # Use fast storage with aggressive mount options
            gpuDevice = 1;  # RX 7600M XT is discrete GPU on card1, card0 is iGPU
          };
        };

        services.audio-context-suspend = {
          enable = true;
          user = "ali";
        };

        # Nullify the disko-generated keyFile so systemd-cryptsetup uses the TPM2 token
        boot.initrd.luks.devices.crypted.keyFile = lib.mkForce null;

        boot = {
          bootspec.enableValidation = true;

          # kernelPackages = pkgs.linuxPackages-rt_latest;
          # kernelPackages = pkgs.linuxPackages;
          # kernelPackages = pkgs.linuxPackages_latest;
          # kernelPackages = pkgs.linuxPackages_lqx;
          # kernelPackages = pkgs.linuxPackages_testing;
          # kernelPackages = pkgs.linuxPackages_xanmod;
          # kernelPackages = pkgs.linuxPackages_zen;
          kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-zen4;

          kernelParams = [
            # "mem_sleep_default=deep"
            "amdgpu.dcdebugmask=0x410"  # Disable PSR + stutter mode (prevents display corruption on RDNA 3 mobile)
            "tc_cmos.use_acpi_alarm=1"

            # RX 7600M XT (Navi 33/RDNA 3) optimizations
            "amdgpu.ppfeaturemask=0xffffffff"  # Enable all PowerPlay features
            "amdgpu.gpu_recovery=1"            # Enable GPU recovery
            "amdgpu.deep_color=1"              # Enable deep color support
            "amdgpu.freesync_video=1"          # Enable FreeSync for video playback
            "amdgpu.aspm=1"                    # Enable ASPM for power savings

          ];

          loader = {
            efi.efiSysMountPoint = "/boot";
            # grub = {
            #   enable = true;
            #   devices = [ "nodev" ];
            #   efiInstallAsRemovable = true;
            #   efiSupport = true;
            #   useOSProber = true;
            #   # theme = pkgs.stdenv.mkDerivation {
            #   #   pname = "distro-grub-themes";
            #   #   version = "3.1";
            #   #   src = pkgs.fetchFromGitHub {
            #   #     owner = "AdisonCavani";
            #   #     repo = "distro-grub-themes";
            #   #     rev = "v3.1";
            #   #     hash = "sha256-ZcoGbbOMDDwjLhsvs77C7G7vINQnprdfI37a9ccrmPs=";
            #   #   };
            #   #   installPhase = "cp -r customize/nixos $out";
            #   # };
            # };
            systemd-boot.enable = lib.mkForce false;
          };
        };

        environment = {
          pathsToLink = [ "/share/zsh" ];

          # RX 7600M XT (RDNA 3) performance optimizations
          variables = {
            # Optimize shader compilation for RDNA 3
            RADV_DEBUG = "zerovram";  # Zero VRAM allocations for better performance
          };

          systemPackages = with pkgs; [
            amdgpu_top
            antigravity
            calibre
            fw-ectool
            framework-tool
            framework-tool-tui
            freeplane
            fuzzel
            gnome-keyring
            inputs.framework-inputmodule-rs-flake.packages.${pkgs.stdenv.hostPlatform.system}.inputmodule-control
            unstable.lact
            ldacbt
            obsidian
            qmk
            qmk-udev-rules
            qmk_hid
            rio
            sbctl
            tpm2-tss
            wireguard-tools
            xdg-desktop-portal-gnome
            xdg-desktop-portal-gtk
            zapzap  # WhatsApp client (replaced whatsie due to insecure qtwebengine-5 dependency)
          ];
        };

        hardware = {
          enableRedistributableFirmware = true;
          keyboard.qmk.enable = true;
          wirelessRegulatoryDatabase = true;

          # Enable Bluetooth with experimental features for better audio performance
          bluetooth = {
            enable = true;
            powerOnBoot = true;
            settings = {
              General = {
                # Enable kernel experimental features (improves audio packet handling)
                Experimental = true;
              };
            };
          };

          fw-fanctrl = {
            enable = true;
            config = {
              defaultStrategy = "agile";
              strategies = {
                "agile" = {
                  fanSpeedUpdateFrequency = 3;
                  movingAverageInterval = 10;
                  speedCurve = [
                    { temp = 0;  speed = 0; }
                    { temp = 50; speed = 15; }
                    { temp = 60; speed = 35; }
                    { temp = 65; speed = 55; }
                    { temp = 70; speed = 70; }
                    { temp = 80; speed = 90; }
                    { temp = 85; speed = 100; }
                  ];
                };
              };
            };
          };

          graphics = {
            enable = true;
            enable32Bit = true;
          };
        };

        networking = {
          hostName = "ali-framework-laptop";

          networkmanager = {
            enable = true;

            wifi = {
              backend = "iwd";
            };

          };

          wireless = {
            iwd = {
              enable = true;
            };
          };
        };


        nix.package = pkgs.nix;

        powerManagement = {
          cpuFreqGovernor = "powersave";
        };

        # Reduce ZRAM for faster hibernation (less data to serialize)
        zramSwap.memoryPercent = lib.mkForce 50;

        programs = {

          niri = {
            enable = true;
            package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri;
          };
        };

        services = {
          udev = {
            packages = [
              inputs.framework-inputmodule-rs-flake.packages.${pkgs.stdenv.hostPlatform.system}.udev
            ];

            extraRules = ''
              # Framework Laptop 16 Keyboard Module - ANSI
              ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0012", ATTR{power/wakeup}="disabled"

              # Framework Laptop 16 RGB Macropad
              ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0013", ATTR{power/wakeup}="disabled"

              # Framework Laptop 16 Numpad Module
              ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0014", ATTR{power/wakeup}="disabled"

              # Framework Laptop 16 Keyboard Module - ISO
              ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0018", ATTR{power/wakeup}="disabled"

              # RX 7600M XT (Navi 33) discrete GPU - PCI ID 1002:7480
              # Set performance level to auto (allows dynamic performance scaling)
              ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0x7480", ATTR{power_dpm_force_performance_level}="auto"

              # Enable runtime power management for discrete GPU when idle
              ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0x7480", ATTR{power/control}="auto"

              # Grant video group access to IIO ambient light sensor for wluma
              SUBSYSTEM=="iio", KERNEL=="iio:device*", ATTR{name}=="als", MODE="0660", GROUP="video"
            '';
          };

          xserver = {
            videoDrivers = [ "amdgpu" ];
          };
        };

        sops = {
          defaultSopsFile = self + "/secrets/main.enc.yaml";
          defaultSopsFormat = "yaml";
          age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
          secrets = {
            # "myservice/my_subdir/my_secret" = {
            #   mode = "0400";
            #   owner = config.users.users.nobody.name;
            #   group = config.users.users.nobody.group;
            #   restartUnits = ["example.service"];
            #   path = "/a/secret/path.yaml";
            #   format = "yaml"; # can be yaml, json, ini, dotenv, binary
            # };
            # home_enc_key = {
            #   mode = "0400";
            #   sopsFile = self + "/secrets/ali-framework-laptop/home-enc-key.enc.bin";
            #   owner = config.users.users.root.name;
            #   group = config.users.users.nobody.group;
            #   path = "/etc/luks/home.key";
            #   format = "binary";
            # };
          };
        };

        system = {
          stateVersion = "24.11";
        };

        systemd = {
          services = {
            lact = {
              description = "AMDGPU Control Daemon";
              after = [ "multi-user.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStartPre = "${pkgs.coreutils}/bin/rm -f /run/lactd.sock";
                ExecStart = "${pkgs.unstable.lact}/bin/lact daemon";
              };
              enable = true;
            };
          };
        };

        users = {
          users = {
            ali = {
              autoSubUidGidRange = true;
              isNormalUser = true;
              description = "Alison Jenkins";
              extraGroups = [ "audio" "gamemode" "libvirt" "libvirtd" "networkmanager" "video" "wheel" "realtime"];
              hashedPasswordFile = "/persistence/passwords/ali";

              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF"
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK2wZMFO69SYvoIIs6Atx/22PVy8wHtYy0MKpYtUMsez phone-ssh-key"
              ];
            };
            lace = {
              autoSubUidGidRange = true;
              isNormalUser = true;
              description = "Lace Jones";
              extraGroups = [ "audio" "libvirtd" "networkmanager" "video" "wheel" ];
              hashedPasswordFile = "/persistence/passwords/lace";
            };
            root = {
              hashedPasswordFile = "/persistence/passwords/root";
            };
          };
        };

        xdg =
          let
            browser = [
              "zen-beta.desktop"
            ];
            editor = [ "nvim.desktop" ];
            excel = [ "libreoffice-calc.desktop" ];
            fileManager = [ "thunar.desktop" ];
            image = [ "feh.desktop" ];
            mail = [ "zen-beta.desktop" ];
            powerpoint = [ "libreoffice-impress.desktop" ];
            terminal = [
              "alacritty.desktop"
            ];
            video = [ "vlc.desktop" ];
            word = [ "libreoffice-writer.desktop" ];

            # XDG MIME types
            associations = {
              "application/json" = editor;
              "application/pdf" = [ "org.pwmt.zathura.desktop" ];
              "application/rss+xml" = editor;
              "application/vnd.ms-excel" = excel;
              "application/vnd.ms-powerpoint" = powerpoint;
              "application/vnd.ms-word" = word;
              "application/vnd.oasis.opendocument.database" = [ "libreoffice-base.desktop" ];
              "application/vnd.oasis.opendocument.formula" = [ "libreoffice-math.desktop" ];
              "application/vnd.oasis.opendocument.graphics" = [ "libreoffice-draw.desktop" ];
              "application/vnd.oasis.opendocument.graphics-template" = [ "libreoffice-draw.desktop" ];
              "application/vnd.oasis.opendocument.presentation" = powerpoint;
              "application/vnd.oasis.opendocument.presentation-template" = powerpoint;
              "application/vnd.oasis.opendocument.spreadsheet" = excel;
              "application/vnd.oasis.opendocument.spreadsheet-template" = excel;
              "application/vnd.oasis.opendocument.text" = word;
              "application/vnd.oasis.opendocument.text-master" = word;
              "application/vnd.oasis.opendocument.text-template" = word;
              "application/vnd.oasis.opendocument.text-web" = word;
              "application/vnd.openxmlformats-officedocument.presentationml.presentation" = powerpoint;
              "application/vnd.openxmlformats-officedocument.presentationml.template" = powerpoint;
              "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" = excel;
              "application/vnd.openxmlformats-officedocument.spreadsheetml.template" = excel;
              "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = word;
              "application/vnd.openxmlformats-officedocument.wordprocessingml.template" = word;
              "application/vnd.stardivision.calc" = excel;
              "application/vnd.stardivision.draw" = [ "libreoffice-draw.desktop" ];
              "application/vnd.stardivision.impress" = powerpoint;
              "application/vnd.stardivision.math" = [ "libreoffice-math.desktop" ];
              "application/vnd.stardivision.writer" = word;
              "application/vnd.sun.xml.base" = [ "libreoffice-base.desktop" ];
              "application/vnd.sun.xml.calc" = excel;
              "application/vnd.sun.xml.calc.template" = excel;
              "application/vnd.sun.xml.draw" = [ "libreoffice-draw.desktop" ];
              "application/vnd.sun.xml.draw.template" = [ "libreoffice-draw.desktop" ];
              "application/vnd.sun.xml.impress" = powerpoint;
              "application/vnd.sun.xml.impress.template" = powerpoint;
              "application/vnd.sun.xml.math" = [ "libreoffice-math.desktop" ];
              "application/vnd.sun.xml.writer" = word;
              "application/vnd.sun.xml.writer.global" = word;
              "application/vnd.sun.xml.writer.template" = word;
              "application/vnd.wordperfect" = word;
              "application/x-arj" = [ "org.kde.ark.desktop" ];
              "application/x-bittorrent" = [ "org.qbittorrent.qBittorrent.desktop" ];
              "application/x-bzip" = [ "org.kde.ark.desktop" ];
              "application/x-bzip-compressed-tar" = [ "org.kde.ark.desktop" ];
              "application/x-compress" = [ "org.kde.ark.desktop" ];
              "application/x-compressed-tar" = [ "org.kde.ark.desktop" ];
              "application/x-extension-htm" = browser;
              "application/x-extension-html" = browser;
              "application/x-extension-ics" = mail;
              "application/x-extension-m4a" = video;
              "application/x-extension-mp4" = video;
              "application/x-extension-shtml" = browser;
              "application/x-extension-xht" = browser;
              "application/x-extension-xhtml" = browser;
              "application/x-flac" = video;
              "application/x-gzip" = [ "org.kde.ark.desktop" ];
              "application/x-lha" = [ "org.kde.ark.desktop" ];
              "application/x-lhz" = [ "org.kde.ark.desktop" ];
              "application/x-lzop" = [ "org.kde.ark.desktop" ];
              "application/x-matroska" = video;
              "application/x-netshow-channel" = video;
              "application/x-quicktime-media-link" = video;
              "application/x-quicktimeplayer" = video;
              "application/x-rar" = [ "org.kde.ark.desktop" ];
              "application/x-shellscript" = editor;
              "application/x-smil" = video;
              "application/x-tar" = [ "org.kde.ark.desktop" ];
              "application/x-tarz" = [ "org.kde.ark.desktop" ];
              "application/x-wine-extension-ini" = [ "org.kde.kate.desktop" ];
              "application/x-zoo" = [ "org.kde.ark.desktop" ];
              "application/xhtml+xml" = browser;
              "application/xml" = editor;
              "application/zip" = [ "org.kde.ark.desktop" ];
              "audio/*" = video;
              "image/*" = image;
              "image/bmp" = [ "org.kde.gwenview.desktop" ];
              "image/gif" = [ "org.kde.gwenview.desktop" ];
              "image/jpeg" = [ "org.kde.gwenview.desktop" ];
              "image/jpg" = [ "org.kde.gwenview.desktop" ];
              "image/pjpeg" = [ "org.kde.gwenview.desktop" ];
              "image/png" = [ "org.kde.gwenview.desktop" ];
              "image/svg+xml" = [ "org.inkscape.Inkscape.desktop" ];
              "image/tiff" = [ "org.kde.gwenview.desktop" ];
              "image/x-compressed-xcf" = [ "gimp.desktop" ];
              "image/x-fits" = [ "gimp.desktop" ];
              "image/x-icb" = [ "org.kde.gwenview.desktop" ];
              "image/x-ico" = [ "org.kde.gwenview.desktop" ];
              "image/x-pcx" = [ "org.kde.gwenview.desktop" ];
              "image/x-portable-anymap" = [ "org.kde.gwenview.desktop" ];
              "image/x-portable-bitmap" = [ "org.kde.gwenview.desktop" ];
              "image/x-portable-graymap" = [ "org.kde.gwenview.desktop" ];
              "image/x-portable-pixmap" = [ "org.kde.gwenview.desktop" ];
              "image/x-psd" = [ "gimp.desktop" ];
              "image/x-xbitmap" = [ "org.kde.gwenview.desktop" ];
              "image/x-xcf" = [ "gimp.desktop" ];
              "image/x-xpixmap" = [ "org.kde.gwenview.desktop" ];
              "image/x-xwindowdump" = [ "org.kde.gwenview.desktop" ];
              "inode/directory" = fileManager;
              "message/rfc822" = mail;
              "text/*" = editor;
              "text/calendar" = mail;
              "text/html" = browser;
              "text/plain" = editor;
              "video/*" = video;
              "x-scheme-handler/about" = browser;
              "x-scheme-handler/chrome" = browser;
              "x-scheme-handler/discord" = [ "vesktop.desktop" ];
              "x-scheme-handler/etcher" = [ "balena-etcher-electron.desktop" ];
              "x-scheme-handler/ftp" = browser;
              "x-scheme-handler/gitkraken" = [ "GitKraken.desktop" ];
              "x-scheme-handler/http" = browser;
              "x-scheme-handler/https" = browser;
              "x-scheme-handler/mailto" = mail;
              "x-scheme-handler/mid" = mail;
              "x-scheme-handler/terminal" = terminal;
              "x-scheme-handler/tg" = [ "org.telegram.desktop" ];
              "x-scheme-handler/unknown" = browser;
              "x-scheme-handler/webcal" = mail;
              "x-scheme-handler/webcals" = mail;
              "x-scheme-handler/x-github-client" = [ "github-desktop.desktop" ];
              "x-scheme-handler/x-github-desktop-auth" = [ "github-desktop.desktop" ];
              "x-www-browser" = browser;
              # "x-scheme-handler/chrome" = ["chromium-browser.desktop"];
            };
          in
          {
            mime = {
              enable = true;
              defaultApplications = associations;
              addedAssociations = associations;
            };
            portal = {
              enable = true;
              xdgOpenUsePortal = true;

              config = {
              };

              extraPortals = with pkgs; [
                xdg-desktop-portal-wlr
              ];
            };
          };
      })
    ];
  };
}
