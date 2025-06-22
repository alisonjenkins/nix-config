{ config
, inputs
, outputs
, pkgs
, lib
, ...
}: {
  imports = [
    # inputs.nix-gaming.nixosModules.pipewireLowLatency
    (import ../../modules/base {
      enableImpermanence = true;
      impermanencePersistencePath = builtins.toPath "/persistence";
      inherit inputs lib;
    })
    (import ../../modules/desktop {
      inherit inputs pkgs lib;
    })
    (import ../../modules/locale { })
    (import ../../modules/vr { enableOpenSourceVR = false; })
    (import ../../modules/ollama)
    (import ../../modules/rocm { inherit pkgs; })
    ../../app-profiles/desktop
    ./hardware-configuration.nix
  ];

  boot = {
    bootspec.enableValidation = true;
    # kernelPackages = pkgs.linuxPackages-rt_latest;
    # kernelPackages = pkgs.linuxPackages;
    # kernelPackages = pkgs.linuxPackages_cachyos;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_xanmod;
    kernelPackages = pkgs.linuxPackages_cachyos-lto;

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
          enable = true;
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
      # libsForQt5.polonium
      # stable.ananicy-cpp-rules
      # system-bridge
      alsa-scarlett-gui
      amdgpu_top
      cifs-utils
      cpu-x
      deadd-notification-center
      drawio
      freeplane
      geekbench
      handbrake
      i2pd
      inkscape
      innoextract
      kdePackages.korganizer
      lact
      libaacs
      lsscsi
      mkvtoolnix
      moonlight-qt
      openrct2
      openttd
      openttd-ttf
      podman
      polkit
      protontricks
      qbittorrent
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
      todoist-electron
      uhk-agent
      unixtools.xxd
      unstable.makemkv
      unzip
      upscayl
      webcamoid
      wireguard-tools
      xd
      xdotool
      xorg.xprop
      xorg.xwininfo
      yad
      yt-dlp
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
        29087
      ];
    };

    nameservers = [
      "9.9.9.9"
      "149.112.112.112"
    ];

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
      # outputs.overlays.alvr
      # outputs.overlays.ffmpeg
      inputs.nur.overlays.default
      inputs.rust-overlay.overlays.default
      outputs.overlays._7zz
      outputs.overlays.additions
      outputs.overlays.bluray-playback
      outputs.overlays.master-packages
      outputs.overlays.modifications
      outputs.overlays.python3PackagesOverlay
      outputs.overlays.qtwebengine
      outputs.overlays.quirc
      outputs.overlays.snapper
      outputs.overlays.stable-packages
      outputs.overlays.tmux-sessionizer
      outputs.overlays.unstable-packages
    ];

    config = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "electron-33.4.11"
      ];
    };
  };

  nix = {
    package = pkgs.nixVersions.stable;
    extraOptions = "experimental-features = nix-command flakes";
    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 60d";
    };

    settings = {
      auto-optimise-store = false;
      trusted-users = [ "root" "@wheel" ];

      substituters = [
        "https://cosmic.cachix.org/"
        "https://hyprland.cachix.org"
      ];
      trusted-public-keys = [
        "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
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

    river = {
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

    # beesd = {
    #   filesystems = {
    #     persistence = {
    #       extraOptions = ["--loadavg-target" "5.0"];
    #       hashTableSizeMB = 2048;
    #       spec = "LABEL=persistence";
    #       verbosity = "crit";
    #     };
    #   };
    # };

    btrfs = {
      autoScrub = {
        enable = true;
        fileSystems = [
          "/persistence"
        ];
      };
    };

    desktopManager = {
      cosmic = {
        enable = true;
      };
    };

    udev = {
      extraRules = ''
        SUBSYSTEM=="pci", DRIVER=="amdgpu", ATTR{power_dpm_force_performance_level}="low"
      '';

      packages = [
        pkgs.uhk-udev-rules
      ];
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
      package = pkgs.unstable.sunshine;
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
      # };
      # home_enc_key = {
      #   format = "binary";
      #   group = config.users.users.nobody.group;
      #   mode = "0400";
      #   neededForUsers = true;
      #   owner = config.users.users.root.name;
      #   path = "/etc/luks/home.key";
      #   sopsFile = ../../secrets/ali-desktop/home-enc-key.enc.bin;
      # };
    };
  };

  system = {
    stateVersion = "24.05";
  };

  systemd = {
    services = {
      lact = {
        description = "AMDGPU Control Daemon";
        after = [ "multi-user.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.lact}/bin/lact daemon";
        };
        enable = true;
      };
    };
    tmpfiles = {
      rules = [ "d /var/cache/jellyfin 1770 jellyfin jellyfin -" ];
    };
  };

  users = {
    defaultUserShell = pkgs.zsh;
    mutableUsers = false;

    groups = {
      jellyfin = {
        gid = 1000;
      };
    };

    users = {
      ali = {
        autoSubUidGidRange = true;
        description = "Alison Jenkins";
        isNormalUser = true;
        hashedPasswordFile = "/persistence/passwords/ali";
        useDefaultShell = true;

        extraGroups = [
          "audio"
          "cdrom"
          "docker"
          "jellyfin"
          "networkmanager"
          "pipewire"
          "video"
          "wheel"
        ];

        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK2wZMFO69SYvoIIs6Atx/22PVy8wHtYy0MKpYtUMsez phone-ssh-key"
        ];
      };
      jellyfin = {
        isNormalUser = false;
        isSystemUser = true;
        uid = 302;
        group = "jellyfin";
        home = "/home/jellyfin";
        createHome = true;
      };
      root = {
        hashedPasswordFile = "/persistence/passwords/root";
      };
    };
  };

  virtualisation = {
    # docker = {
    #   enable = true;
    # };

    podman = {
      autoPrune.enable = true;
      dockerCompat = true;
      dockerSocket.enable = true;
      enable = true;
    };

    libvirtd = {
      enable = true;
      qemu.swtpm.enable = true;
      qemu.ovmf = {
        enable = true;
        packages = [ pkgs.OVMFFull.fd ];
      };
    };

    oci-containers = {
      containers = {
        jellyfin = {
          autoStart = true;
          # pull = "always";
          image = "docker.io/jellyfin/jellyfin:latest";
          serviceName = "jellyfin";
          user = "1001:1000";

          environment = {
            HEALTHCHECK_URL = "http://localhost:29087/health";
          };

          extraOptions = [
            # "--device /dev/dri:/dev/dri"
            "--network=host"
          ];

          labels = {
            "io.containers.autoupdate" = "registry";
          };

          ports = [
            "0.0.0.0:29087:29087"
          ];

          volumes = [
            "/var/cache/jellyfin:/cache"
            "/home/jellyfin/config:/config"
            "/media/storage1/Media:/media"
          ];
        };
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
        };

        extraPortals = with pkgs; [
          kdePackages.xdg-desktop-portal-kde
          xdg-desktop-portal-cosmic
          xdg-desktop-portal-wlr
        ];
      };
    };
}
