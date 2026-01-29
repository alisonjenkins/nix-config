{ config
, inputs
, outputs
, pkgs
, lib
, system
, ...
}: {
  imports = [
    # inputs.nix-gaming.nixosModules.pipewireLowLatency
    (import ../../modules/base {
      enableImpermanence = true;
      impermanencePersistencePath = builtins.toPath "/persistence";
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
      inherit inputs lib outputs pkgs;
      useSecureBoot = true;
    })
    ../../modules/desktop
    (import ../../modules/locale { })
    (import ../../modules/vr { enableOpenSourceVR = false; inherit lib; })
    (import ../../modules/ollama)
    (import ../../modules/rocm { inherit pkgs; })
    ../../app-profiles/desktop
    ./hardware-configuration.nix
  ];

  modules.desktop = {
    enable = true;

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
    ];

    initrd = {
      availableKernelModules = [ "r8169" ];

      systemd = {
        enable = true;

        initrdBin = with pkgs; [
          cryptsetup
        ];

        users = {
          root = {
            shell = "/bin/cryptsetup-askpass";
          };
        };

        network = {
          networks = {
            "enp16s0" = {
              matchConfig = {
                Name = "enp16s0"; # Matches the network interface by name
              };
              networkConfig = {
                DHCP = "yes"; # Enable DHCP to automatically get an IP address
              };
            };
          };
        };

        # Define the service that will handle LUKS unlocking
        # services = {
        #   unlock-luks = {
        #     description = "Unlock LUKS encrypted root device";
        #     # Make sure this service runs during boot
        #     wantedBy = [ "initrd.target" ];
        #     # Wait for network to be ready before trying to unlock
        #     after = [ "network-online.target" ];
        #     # Must unlock before trying to mount the root filesystem
        #     before = [ "sysroot.mount" ];
        #     # Ensure necessary tools are available
        #     path = [ "/bin" ];
        #
        #     # Configure how the service behaves
        #     serviceConfig = {
        #       Type = "oneshot"; # Service runs once and exits
        #       RemainAfterExit = true; # Consider service active even after it exits
        #       SuccessExitStatus = [ 0 1 ]; # Both 0 and 1 are considered success
        #     };
        #
        #     # The actual commands to unlock the drive
        #     script = ''
        #       echo "Waiting for LUKS unlock..."
        #       # Try to unlock the encrypted drive
        #       # The || true ensures the script doesn't fail if first attempt fails
        #       cryptsetup open /dev/disk/by-uuid/251edf6c-ec46-4734-97ad-1caab10a6246 root --type luks || true
        #     '';
        #   };
        # };
      };

      network = {
        enable = true;

        # postCommands =
        #   let
        #     # Replace this with your LUKS device path !!!
        #     # See previous step
        #     disk = "/dev/disk/by-uuid/251edf6c-ec46-4734-97ad-1caab10a6246";
        #   in
        #   ''
        #     echo 'cryptsetup open ${disk} root --type luks && echo > /tmp/unlocked' >> /root/.profile
        #     echo 'Starting SSH server for remote LUKS decryption...'
        #   '';
        #
        # # Block boot until the LUKS device is unlocked
        # postDeviceCommands = ''
        #   echo 'Waiting for root device to be unlocked...'
        #   mkfifo /tmp/unlocked
        #   cat /tmp/unlocked
        # '';

        ssh = {
          enable = false;
          port = 2222;

          authorizedKeys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF"
          ];

          hostKeys = [
            "/etc/ssh/initrd/ssh_host_key_ed25519"
            "/etc/ssh/initrd/ssh_host_key_rsa"
          ];
        };
      };
    };

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
      claude-code
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
      kdePackages.korganizer
      lact
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
      todoist-electron
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
      (import ../../overlays { inherit inputs lib; system = "x86_64-linux"; }).lqx-pin-packages
      inputs.niri-flake.overlays.niri
    ];
  };

  nix = {
    package = pkgs.nix;
    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 60d";
    };

    settings = {
      auto-optimise-store = false;
      trusted-users = [ "root" "@wheel" ];
    };
  };

  powerManagement = {
    cpuFreqGovernor = "performance";
  };

  programs = {
    java = {
      enable = true;
      package = pkgs.jdk17;
    };

    niri = {
      enable = true;
      package = pkgs.niri-unstable;
    };

    steam = let
      patchedBwrap = pkgs.bubblewrap.overrideAttrs (old: {
        patches = (old.patches or []) ++ [
          ../../patches/bubblewrap-allow-caps.patch
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

      # settings = {
      #   apply_settings_timer = 5;
      #
      #   daemon = {
      #     admin_group = "wheel";
      #     disable_clocks_cleanup = false;
      #     log_level = "info";
      #     tcp_listen_address = "127.0.0.1:12853";
      #
      #     metrics = {
      #       collector_address = "http://localhost:9090/api/v1/otlp/v1/metrics";
      #       interval = 30;
      #     };
      #   };
      #
      #   gpus = {
      #     "1002:7550-1DA2:E489-0000:03:00.0" = {
      #       fan_control_enabled = false;
      #       power_cap = 374.0;
      #       performance_level = "auto";
      #       voltage_offset = -130;
      #     };
      #   };
      # };
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

    system76-scheduler = {
      enable = true;
      settings = {
        processScheduler = {
          pipewireBoost = {
            enable = true;
            profile = {
              ioClass = "realtime";
              class = "fifo";
              prio = "80";
            };
          };
        };
      };
    };

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
    defaultSopsFile = ../../secrets/main.enc.yaml;
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
  #     #   sopsFile = ../../secrets/ali-desktop/home-enc-key.enc.bin;
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
        extraGroups = [ "audio" "docker" "libvirtd" "networkmanager" "video" "wheel" "realtime" ];
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
    docker = {
      enable = true;
      enableOnBoot = false;

      autoPrune = {
        enable = true;
      };
    };

    # podman = {
    #   autoPrune.enable = true;
    #   dockerCompat = true;
    #   dockerSocket.enable = true;
    #   enable = true;
    # };

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
        "firefox.desktop"
      ];
      editor = [ "nvim.desktop" ];
      excel = [ "libreoffice-calc.desktop" ];
      fileManager = [ "thunar.desktop" ];
      image = [ "feh.desktop" ];
      mail = [ "firefox.desktop" ];
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
          KDE = {
            default = [
              "kde"
            ];
          };
          niri = {
            default = [
              "gtk"
              "gnome"
            ];
          };
        };

        extraPortals = with pkgs; [
          kdePackages.xdg-desktop-portal-kde
          xdg-desktop-portal-cosmic
          xdg-desktop-portal-gnome
          xdg-desktop-portal-gtk
          xdg-desktop-portal-wlr
        ];
      };
    };
}
