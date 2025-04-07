{ lib
, inputs
, outputs
, pkgs
, ...
}: {
  imports = [
    (import ../../modules/locale { })
    (import ../../modules/libvirtd { inherit pkgs; })
    (import ../../modules/rocm { inherit pkgs; })
    (import ../../modules/base {
      enableImpermanence = true;
      impermanencePersistencePath = builtins.toPath "/persistence";
      inherit inputs lib;
    })
    (import ../../modules/desktop {
      inherit inputs pkgs lib;
    })
    (import ../../modules/vr { enableOpenSourceVR = false; })
    (import ../../modules/ollama)
    ../../app-profiles/desktop
    ../../app-profiles/desktop/kwallet
    (import ../../app-profiles/hardware/fingerprint-reader { username = "ali"; })
    ../../app-profiles/hardware/touchpad
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  boot = {
    bootspec.enableValidation = true;
    # kernelPackages = pkgs.linuxPackages-rt_latest;
    # kernelPackages = pkgs.linuxPackages;
    # kernelPackages = pkgs.linuxPackages_cachyos-lto;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_xanmod;
    # kernelPackages = pkgs.linuxPackages_zen;
    kernelPackages = pkgs.linuxPackages_cachyos;

    kernelParams = [
      # "mem_sleep_default=deep"
      "tc_cmos.use_acpi_alarm=1"
    ];

    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
    };

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

    systemPackages = with pkgs; [
      calibre
      framework-tool
      freeplane
      ldacbt
      qmk
      qmk-udev-rules
      qmk_hid
      rio
      sbctl
      tpm2-tss
      wireguard-tools
    ];
  };

  hardware = {
    enableRedistributableFirmware = true;
    keyboard.qmk.enable = true;
    wirelessRegulatoryDatabase = true;

    graphics = {
      enable = true;
      enable32Bit = true;
    };
  };

  networking = {
    hostName = "ali-framework-laptop";
    extraHosts = ''
      192.168.1.202 home-kvm-hypervisor-1
    '';
    networkmanager.enable = true;
  };

  nix = {
    package = pkgs.nix;
    extraOptions = "experimental-features = nix-command flakes";

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
        "https://nix-community.cachix.org"
      ];

      trusted-public-keys = [
        "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  nixpkgs = {
    overlays = [
      inputs.nur.overlays.default
      inputs.rust-overlay.overlays.default
      outputs.overlays.additions
      outputs.overlays.bacon-nextest
      outputs.overlays.master-packages
      outputs.overlays.modifications
      outputs.overlays.stable-packages
      outputs.overlays.tmux-sessionizer
      outputs.overlays.unstable-packages
      outputs.overlays.zk
    ];
    config = {
      allowUnfree = true;
    };
  };

  services = {
    fwupd = {
      enable = true;
    };

    logind = {
      lidSwitch = "suspend-then-hibernate";
    };

    xserver = {
      videoDrivers = [ "amdgpu" ];
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
      #   mode = "0400";
      #   sopsFile = ../../secrets/ali-framework-laptop/home-enc-key.enc.bin;
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
    sleep = {
      extraConfig = ''
        HibernateDelaySec=30m
        SuspendState=mem
      '';
    };
  };

  users = {
    users = {
      ali = {
        autoSubUidGidRange = true;
        isNormalUser = true;
        description = "Alison Jenkins";
        extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" "video" ];
        hashedPasswordFile = "/persistence/passwords/ali";
      };
      root = {
        hashedPasswordFile = "/persistence/passwords/root";
      };
    };
  };

  virtualisation = {
    docker = {
      enable = true;
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
        ];
      };
    };
}
