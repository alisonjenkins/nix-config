{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
  bluetoothMacs = {
    sonyHeadset = "88:C9:E8:06:5E:9C";
  };
in {
  flake.nixosConfigurations.ali-desktop = lib.nixosSystem rec {
    specialArgs = {
      username = "ali";
      inherit inputs outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }

      # Custom modules via flake outputs
      self.nixosModules.ali-desktop-hardware
      self.nixosModules.desktop-1password
      self.nixosModules.desktop-aws-tools
      self.nixosModules.desktop-base
      self.nixosModules.desktop-greetd-regreet
      self.nixosModules.desktop-kde-connect
      self.nixosModules.desktop-kubernetes
      self.nixosModules.desktop-local-k8s
      self.nixosModules.desktop-media
      self.nixosModules.audio-context-suspend
      self.nixosModules.base
      self.nixosModules.desktop
      self.nixosModules.locale
      self.nixosModules.niks3-cache-push
      self.nixosModules.nohang
      self.nixosModules.ollama
      self.nixosModules.uresourced
      self.nixosModules.plymouth
      self.nixosModules.podman
      self.nixosModules.rocm
      self.nixosModules.tts
      self.nixosModules.vr

      # External flake modules
      inputs.nix-flatpak.nixosModules.nix-flatpak
      inputs.nur.modules.nixos.default
      inputs.sops-nix.nixosModules.sops
      inputs.home-manager.nixosModules.home-manager

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
          imports = [ self.homeModules.home-linux ];
          custom.niri.extraOutputs = ''
            output "DP-2" {
                variable-refresh-rate
            }
          '';
        };
        home-manager.extraSpecialArgs =
          specialArgs
          // {
            hostname = "ali-desktop";
            bluetoothHeadsetMac = bluetoothMacs.sonyHeadset;
            gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            gitGPGSigningKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF";
            gitUserName = "Alison Jenkins";
            github_clone_ssh_host_personal = "github.com";
            github_clone_ssh_host_work = "github.com";
            primarySSHKey = "~/.ssh/id_personal.pub";
          };
      }

      ({ config, pkgs, lib, ... }: {
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

        modules.desktop-1password.enable = true;
        modules.desktop-aws-tools.enable = true;
        modules.desktop-base.enable = true;
        modules.desktop-greetd-regreet.enable = true;
        modules.desktop-kde-connect.enable = true;
        modules.desktop-kubernetes.enable = true;
        modules.desktop-local-k8s.enable = true;
        modules.desktop-media.enable = true;
        modules.plymouth.enable = true;
        modules.nohang = {
          enable = true;
          enableDesktopNotifications = true;
        };
        modules.uresourced.enable = true;
        modules.base = {
          enable = true;
          enableImpermanence = true;
          bootLoader = "secure-boot";
          enableCachyOSKernel = true;
          # Set to null: the stale literal value no longer matched what new
          # generations measure into PCR 15, causing check-pcrs to exit 1 and
          # block sysroot.mount. Recapture the real value from the initrd
          # emergency shell (`systemd-analyze pcrs 15 --json=short`) and
          # restore a literal here once the boot-fix dust settles.
          pcr15Value = null;
          beesdFilesystems = {
            persistence = {
              spec = "LABEL=persistence";
              hashTableSizeMB = 2048;
              verbosity = "crit";
              extraOptions = [ "--loadavg-target" "15.0" ];
            };
            steam-storage-1 = {
              spec = "LABEL=steam-games-1";
              hashTableSizeMB = 2048;
              verbosity = "crit";
              extraOptions = [ "--loadavg-target" "15.0" ];
            };
          };
        };
        nix.settings.cores = 16;
        nix.settings.max-jobs = 8;

        modules.locale.enable = true;
        modules.ollama.enable = true;
        modules.podman.enable = true;
        modules.podman.enableQemuBinfmt = true;
        modules.rocm.enable = true;
        modules.tts.enable = true;

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
              height = 0.25;
              offset_x = 0.0;
              offset_y = 0.0;
            }
            {
              encoder = "vaapi";
              codec = "av1";
              width = 1.0;
              height = 0.25;
              offset_x = 0.0;
              offset_y = 0.25;
            }
            {
              encoder = "vaapi";
              codec = "av1";
              width = 1.0;
              height = 0.25;
              offset_x = 0.0;
              offset_y = 0.5;
            }
            {
              encoder = "vaapi";
              codec = "av1";
              width = 1.0;
              height = 0.25;
              offset_x = 0.0;
              offset_y = 0.75;
            }
          ];
        };

        modules.desktop = {
          enable = true;

          network.cakeMode = "besteffort";

          pipewire = {
            suspendTimeoutSeconds = 0;  # Never suspend audio devices — prevents crackle on resume
            alsaHeadroom = 2048;        # Extra headroom to absorb scheduling jitter under CPU load
          };

          gaming = {
            gpuVendor = "amd";
            cpuTopology = "16:32";  # Ryzen 9 7950X: 16 cores, 32 threads
            enableDxvkStateCache = true;
            enableVkd3dShaderCache = true;
            dxvkHud = "0";  # Disable HUD for performance (use "fps" or "compiler" for debugging)
            enableLargeAddressAware = true;
            shaderCacheBasePath = "/media/steam-games-1/.shader-cache";  # Use high-performance volume
          };
        };

        # Create shader cache directory on steam-games volume
        systemd.tmpfiles.rules = [
          "d /media/steam-games-1/.shader-cache 0755 ali users -"
        ];


        services.audio-context-suspend = {
          enable = true;
          user = "ali";
        };

        boot = {
          bootspec.enableValidation = true;
          # kernelPackages = pkgs.linuxPackages-rt_latest;
          # kernelPackages = pkgs.linuxPackages_latest;
          # kernelPackages = pkgs.linuxPackages_lqx;
          # kernelPackages = pkgs.linuxPackages_xanmod;
          # kernelPackages = pkgs.lqx_pin.linuxKernel.packages.linux_lqx;
          kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-zen4;

          kernelParams = [
            # AMD GPU optimized for RDNA 4 (GFX1201) - BIOS 3.50 + LQX kernel
            "amdgpu.ppfeaturemask=0xffffffff"  # Enable all PowerPlay features
            "amdgpu.gpu_recovery=1"            # Enable GPU recovery
            "amdgpu.dc=1"                      # Enable Display Core (DC)
            "amdgpu.dpm=1"                     # Enable Dynamic Power Management

            # Performance optimizations (stability issues resolved with BIOS/kernel fix)
            "amdgpu.vm_fragment_size=9"        # Use 2MB page fragments (optimal for RDNA)
            "amdgpu.vm_update_mode=0"          # Use default (auto) VM update mode for best performance

            # Allow PCI bridge window reallocation when devices appear after initial scan
            "pci=realloc"
          ];

          loader = {
            grub = {
              memtest86.enable = true;
            };
          };
        };

        environment = {
          pathsToLink = [ "/share/zsh" ];

          etc = {
            "crypttab".text = ''
              # <name>       <device>                                     <password>              <options>
              home1          UUID=ee7395ed-e76a-4179-8e92-42e35250e98d    /etc/luks/home.key
              home2          UUID=1ac3af7c-5af5-4972-b4b6-0245cc072a65    /etc/luks/home.key
            '';
          };

          systemPackages = with pkgs; [
            # deadd-notification-center
            alsa-scarlett-gui
            amdgpu_top
            antigravity
            cifs-utils
            cpu-x
            drawio
            freeplane
            gcc
            geekbench
            gemini-cli
            handbrake
            i2pd
            inkscape
            innoextract
            unstable.lact
            libaacs
            lsscsi
            master.yt-dlp
            mkvtoolnix
            moonlight-qt
            openrct2
            openttd
            openttd-ttf
            podman
            protontricks
            protonvpn-gui
            qbittorrent
            qemu_full
            radeontop
            rio
            s-tui
            stable.ananicy-cpp
            stress
            sunshine
            sweethome3d.application
            sweethome3d.furniture-editor
            sweethome3d.textures-editor
            sysbench
            tiny4linux
            unixtools.xxd
            unstable.makemkv
            unstable.uhk-agent
            unzip
            upscayl
            webcamoid
            wireguard-tools
            xd
            xdotool
            xorg.xprop
            xorg.xwininfo
            yad
            zk
          ];

          variables = {
            PATH = [ "\${HOME}/.local/bin" "\${HOME}/.config/rofi/scripts" ];
          };
        };

        hardware = {
          cpu = {
            amd = {
              updateMicrocode = true;
            };
          };
        };

        # Disable NetworkManager-wait-online — desktop doesn't need network up before login
        systemd.services.NetworkManager-wait-online.enable = false;

        # PCIe link training workaround: the RTL8125 NIC at 10:00.0 is behind 6
        # levels of PCIe switches on X670E (root port 00:02.1 → ... → 0c:03.0 →
        # 10:00.0). A smaller UKI changes UEFI load timing, so the kernel scans PCI
        # before all links finish training. Bridge 0c:03.0 sees no device and its
        # IO/mem windows get freed and claimed by the GPU root port (00:08.1).
        #
        # In the initrd, no SATA filesystems behind 00:02.1 are mounted (rootfs is
        # on NVMe behind a different root port), so it's safe to remove the entire
        # root port subtree and rescan. pci=realloc allows bridge windows to be
        # reassigned during the rescan.
        # PCIe link training workaround moved to userspace (was in initrd).
        # Root filesystem is on NVMe behind a different root port, so the NIC rescan
        # doesn't need to block initrd. Running in userspace before NetworkManager
        # saves ~9s from initrd while still ensuring the NIC is available for networking.
        systemd.services.pci-rescan-nic = {
          description = "Rescan PCI bus for late-training RTL8125 NIC";
          unitConfig = {
            ConditionPathExists = "!/sys/bus/pci/devices/0000:10:00.0";
          };
          after = [ "systemd-udev-settle.service" ];
          before = [ "NetworkManager.service" "network-pre.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ pkgs.coreutils ];
          script = ''
            echo "RTL8125 not detected at 10:00.0, removing root port 00:02.1 subtree and rescanning..."
            if [ -e /sys/bus/pci/devices/0000:00:02.1/remove ]; then
              echo 1 > /sys/bus/pci/devices/0000:00:02.1/remove
            fi
            sleep 8
            echo 1 > /sys/bus/pci/rescan
            sleep 1
            if [ -e /sys/bus/pci/devices/0000:10:00.0 ]; then
              echo "RTL8125 detected at 10:00.0 after rescan"
            else
              echo "RTL8125 not found, waiting and rescanning again..."
              sleep 4
              echo 1 > /sys/bus/pci/devices/0000:00:02.1/remove 2>/dev/null || true
              sleep 8
              echo 1 > /sys/bus/pci/rescan
              sleep 1
              if [ -e /sys/bus/pci/devices/0000:10:00.0 ]; then
                echo "RTL8125 detected at 10:00.0 after second rescan"
              else
                echo "WARNING: RTL8125 still not detected"
              fi
            fi
          '';
        };

        networking = {
          hostName = "ali-desktop";

          firewall = {
            allowedTCPPorts = [
              # 29087
            ];
          };

          # nameservers = [
          #   "9.9.9.9"
          #   "149.112.112.112"
          # ];

          interfaces = {
            "enp16s0" = {
              wakeOnLan = {
                enable = true;
              };
            };
          };
        };

        nixpkgs = {
          overlays = [
            self.overlays.lqx-pin-packages
          ];
        };

        nix = {
          package = pkgs.nix;
          nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
        };

        # Hard-cap nix-daemon to 75% of CPU (24 of 32 threads) to prevent memory bandwidth
        # saturation that causes audio crackling during gaming. The existing CPUWeight=50 +
        # batch scheduling in the desktop module handles soft priority, but CPUQuota provides
        # a hard kernel-enforced ceiling that guarantees headroom for PipeWire and games.
        systemd.services.lactd.serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/rm -f /run/lactd.sock";
        systemd.services.nix-daemon.serviceConfig.CPUQuota = "2880%";

        powerManagement = {
          cpuFreqGovernor = "performance";
        };

        # Set PPD to balanced on boot — desktop is always on AC, no reason for power-saver.
        # cpuFreqGovernor is overridden by PPD when active, but kept as fallback.
        systemd.services.ppd-set-balanced = {
          description = "Set power-profiles-daemon to balanced profile";
          after = [ "power-profiles-daemon.service" ];
          requires = [ "power-profiles-daemon.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced";
          };
        };

        programs = {
          java = {
            enable = true;
            package = pkgs.jdk17;
          };

          niri = {
            enable = true;
            package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri;
          };

          steam = let
            patchedBwrap = pkgs.bubblewrap.overrideAttrs (old: {
              patches = (old.patches or []) ++ [
                (self + "/patches/bubblewrap-allow-caps.patch")
              ];
            });
          in {
            enable = true;
            package = pkgs.steam.override {
              buildFHSEnv = args: (pkgs.buildFHSEnv.override {
                bubblewrap = patchedBwrap;
              }) (args // {
                extraBwrapArgs = (args.extraBwrapArgs or []) ++ [ "--cap-add" "ALL" ];
              });
              # Add patched bubblewrap inside FHS environment and tell pressure-vessel to use it
              extraPkgs = pkgs: [ patchedBwrap ];
              extraEnv = {
                # Tell pressure-vessel to use the patched bubblewrap instead of its bundled one
                BWRAP = "${patchedBwrap}/bin/bwrap";
              };
            };
          };

          sway = {
            enable = true;
          };
        };

        # security = {
        #   wrappers = {
        #     sunshine = {
        #       owner = "root";
        #       group = "root";
        #       capabilities = "cap_sys_admin+p";
        #       source = "${pkgs.sunshine}/bin/sunshine";
        #     };
        #   };
        # };

        services = {
          avahi = {
            publish = {
              enable = true;
              userServices = true;
            };
          };

          btrfs = {
            autoScrub = {
              enable = true;
              fileSystems = [
                "/persistence"
              ];
            };
          };

          desktopManager = {
            # cosmic = {
            #   enable = true;
            # };
          };

          udev = {
            packages = [
              pkgs.uhk-udev-rules
            ];
            extraRules = ''
              # Fix 8BitDo Ultimate Wireless Controller connection issues (autosuspend)
              ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2dc8", ATTR{idProduct}=="3106", ATTR{power/control}="on"
            '';
          };

          lact = {
            enable = true;
            package = pkgs.unstable.lact;

            settings = {
              version = 5;
              apply_settings_timer = 5;

              daemon = {
                admin_group = "wheel";
                disable_clocks_cleanup = false;
                log_level = "info";
              };

              gpus = {
                "1002:7550-1DA2:E489-0000:03:00.0" = {
                  fan_control_enabled = false;
                  power_cap = 374.0;
                  performance_level = "auto";
                  voltage_offset = -80;
                };
              };
            };
          };

          snapper = {
            persistentTimer = true;
            configs = {
              nix = {
                SUBVOLUME = "/nix";
                ALLOW_USERS = [ "ali" ];
                TIMELINE_CREATE = true;
                TIMELINE_CLEANUP = true;
              };

              persistence = {
                SUBVOLUME = "/persistence";
                ALLOW_USERS = [ "ali" ];
                TIMELINE_CREATE = true;
                TIMELINE_CLEANUP = true;
              };
            };
          };

          # system76-scheduler disabled: its session-services cgroup rule uses sched_setattr()
          # to set nice values, which clobbers PipeWire's SCHED_FIFO|SCHED_RESET_ON_FORK.
          # Its CFS latency profiles are also redundant with scx_lavd.
          # Process scheduling is handled by ananicy-cpp with ananicy-rules-cachyos.
          system76-scheduler.enable = false;

          sunshine = {
            enable = true;
            autoStart = true;
            capSysAdmin = true;
            openFirewall = true;
            package = pkgs.unstable.sunshine;

            applications = {
              env = {
                PATH = "$(PATH):$(HOME)/.local/bin";
              };
              apps = [
                {
                  name = "Desktop";
                  image-path = "desktop.png";
                }
                {
                  name = "Steam Big Picture";
                  detached = [
                    "sunshine-steam-bp"
                  ];
                  prep-cmd = [
                    {
                      undo = "setsid steam steam://close/bigpicture";
                    }
                  ];
                  image-path = "steam.png";
                }
                {
                  name = "Steam Big Picture (TV 1080p)";
                  detached = [
                    "sunshine-steam-bp"
                  ];
                  prep-cmd = [
                    {
                      do = "niri msg output DP-2 mode 1920x1080@120.000";
                      undo = "niri msg output DP-2 mode 5120x1440@119.999";
                    }
                    {
                      undo = "setsid steam steam://close/bigpicture";
                    }
                  ];
                  image-path = "steam.png";
                  auto-detach = "true";
                }
                {
                  name = "TV Desktop (1080p)";
                  prep-cmd = [
                    {
                      do = "niri msg output DP-2 mode 1920x1080@120.000";
                      undo = "niri msg output DP-2 mode 5120x1440@119.999";
                    }
                  ];
                  image-path = "desktop.png";
                }
                {
                  name = "TV Desktop (1440p)";
                  prep-cmd = [
                    {
                      do = "niri msg output DP-2 mode 2560x1440@119.998";
                      undo = "niri msg output DP-2 mode 5120x1440@119.999";
                    }
                  ];
                  image-path = "desktop.png";
                }
                {
                  name = "Gamescope 1080p";
                  detached = [
                    "env ENABLE_GAMESCOPE_WSI=1 sunshine-gamescope 1080p"
                  ];
                  prep-cmd = [
                    {
                      undo = "pkill -f 'gamescope.*steam'";
                    }
                  ];
                  image-path = "steam.png";
                }
                {
                  name = "Gamescope 1440p";
                  detached = [
                    "env ENABLE_GAMESCOPE_WSI=1 sunshine-gamescope 1440p"
                  ];
                  prep-cmd = [
                    {
                      undo = "pkill -f 'gamescope.*steam'";
                    }
                  ];
                  image-path = "steam.png";
                }
              ];
            };
          };

          xserver = {
            videoDrivers = [ "amdgpu" ];
            xkb.layout = "us";
            xkb.variant = "";

            displayManager = {
              importedVariables = [
                "XDG_SESSION_TYPE"
                "XDG_CURRENT_DESKTOP"
                "XDG_SESSION_DESKTOP"
              ];
            };
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
        #     # };
        #     # home_enc_key = {
        #     #   format = "binary";
        #     #   group = config.users.users.nobody.group;
        #     #   mode = "0400";
        #     #   neededForUsers = true;
        #     #   owner = config.users.users.root.name;
        #     #   path = "/etc/luks/home.key";
        #     #   sopsFile = self + "/secrets/ali-desktop/home-enc-key.enc.bin";
        #     # };
          };
        };

        system = {
          stateVersion = "25.05";
        };

        users = {
          users = {
            ali = {
              autoSubUidGidRange = true;
              isNormalUser = true;
              description = "Alison Jenkins";
              extraGroups = [ "audio" "libvirtd" "networkmanager" "podman" "video" "wheel" "realtime" ];
              hashedPasswordFile = "/persistence/passwords/ali";
              useDefaultShell = true;

              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF"
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK2wZMFO69SYvoIIs6Atx/22PVy8wHtYy0MKpYtUMsez phone-ssh-key"
              ];
            };
            root = {
              hashedPasswordFile = "/persistence/passwords/root";
            };
          };
        };

        virtualisation = {
          libvirtd = {
            enable = false;
            qemu.swtpm.enable = true;
          };

          oci-containers = {
            containers = {
              # jellyfin = {
              #   autoStart = true;
              #   # pull = "always";
              #   image = "docker.io/jellyfin/jellyfin:latest";
              #   serviceName = "jellyfin";
              #   user = "1001:1000";
              #
              #   environment = {
              #     HEALTHCHECK_URL = "http://localhost:29087/health";
              #   };
              #
              #   extraOptions = [
              #     # "--device /dev/dri:/dev/dri"
              #     "--network=host"
              #   ];
              #
              #   labels = {
              #     "io.containers.autoupdate" = "registry";
              #   };
              #
              #   ports = [
              #     "0.0.0.0:29087:29087"
              #   ];
              #
              #   volumes = [
              #     "/var/cache/jellyfin:/cache"
              #     "/home/jellyfin/config:/config"
              #     "/media/storage1/Media:/media"
              #   ];
              # };
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
                niri = {
                  default = [
                    "gtk"
                    "gnome"
                  ];
                };
              };

              extraPortals = with pkgs; [
                xdg-desktop-portal-gnome
                xdg-desktop-portal-gtk
                xdg-desktop-portal-wlr
              ];
            };
          };
      })
    ];
  };
}
