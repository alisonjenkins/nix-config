{ lib
, inputs
, outputs
, pkgs
, ...
}: {
  imports = [
    ../../app-profiles/desktop
    ../../app-profiles/desktop/kwallet
    ../../app-profiles/hardware/fingerprint-reader
    ../../app-profiles/hardware/touchpad
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  boot = {
    # kernelPackages = pkgs.linuxPackages-rt_latest;
    # kernelPackages = pkgs.linuxPackages;
    # kernelPackages = pkgs.linuxPackages_cachyos;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_xanmod;
    # kernelPackages = pkgs.linuxPackages_zen;
    kernelPackages = pkgs.linuxPackages_cachyos-lto;

    loader = {
      efi.efiSysMountPoint = "/boot";
      grub = {
        enable = true;
        devices = [ "nodev" ];
        efiInstallAsRemovable = true;
        efiSupport = true;
        useOSProber = true;
        # theme = pkgs.stdenv.mkDerivation {
        #   pname = "distro-grub-themes";
        #   version = "3.1";
        #   src = pkgs.fetchFromGitHub {
        #     owner = "AdisonCavani";
        #     repo = "distro-grub-themes";
        #     rev = "v3.1";
        #     hash = "sha256-ZcoGbbOMDDwjLhsvs77C7G7vINQnprdfI37a9ccrmPs=";
        #   };
        #   installPhase = "cp -r customize/nixos $out";
        # };
      };
    };
  };

  console.keyMap = "us";

  chaotic = {
    mesa-git = {
      enable = false;
      # method = "GBM_BACKENDS_PATH";
    };
  };

  environment = {
    pathsToLink = [ "/share/zsh" ];

    persistence = {
      "/persistence" = {
        hideMounts = true;
        directories = [
          "/etc/NetworkManager/system-connections"
          "/etc/luks"
          "/etc/ssh"
          "/var/lib/bluetooth"
          "/var/lib/flatpak"
          "/var/lib/fprint"
          "/var/lib/nixos"
          "/var/lib/power-profiles-daemon"
          "/var/lib/sddm"
          "/var/lib/systemd/coredump"
          "/var/log"
          {
            directory = "/var/lib/colord";
            user = "colord";
            group = "colord";
            mode = "u=rwx,g=rx,o=";
          }
          {
            directory = "/var/cache/tuigreet";
            user = "greetd";
            group = "greetd";
            mode = "u=rwx,g=rx,o=";
          }
        ];
        files = [
          "/etc/machine-id"
          {
            file = "/var/keys/secret_file";
            parentDirectory = { mode = "u=rwx,g=,o="; };
          }
        ];
      };
    };

    systemPackages = with pkgs; [
      framework-tool
      ldacbt
    ];

    variables = {
      NIXOS_OZONE_WL = "1";
      ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
    };
  };

  hardware = {
    graphics.enable = true;
    pulseaudio.enable = false;
    wirelessRegulatoryDatabase = true;
  };

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_GB.UTF-8";
    LC_IDENTIFICATION = "en_GB.UTF-8";
    LC_MEASUREMENT = "en_GB.UTF-8";
    LC_MONETARY = "en_GB.UTF-8";
    LC_NAME = "en_GB.UTF-8";
    LC_NUMERIC = "en_GB.UTF-8";
    LC_PAPER = "en_GB.UTF-8";
    LC_TELEPHONE = "en_GB.UTF-8";
    LC_TIME = "en_GB.UTF-8";
  };

  musnix = {
    enable = true;
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
    ];
    config = {
      allowUnfree = true;
    };
  };

  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
    };
    zsh.enable = true;
  };

  security.rtkit.enable = true;

  services = {
    auto-cpufreq = {
      enable = false;

      settings = {
        battery = {
          governor = "powersave";
          turbo = "never";
        };
        charger = {
          governor = "performance";
          turbo = "auto";
        };
      };
    };

    fwupd = {
      enable = true;
    };

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    power-profiles-daemon.enable = lib.mkForce true;

    thermald = {
      enable = true;
    };

    xserver = {
      videoDrivers = [
        "fbdev"
        "intel"
        "modesetting"
      ];
      xkb = {
        layout = "us";
        variant = "";
      };
    };
  };

  stylix =
    let
      wallpaper = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/alisonjenkins/nix-config/refs/heads/main/home/wallpapers/5120x1440/Static/sakura.jpg";
        hash = "sha256-rosIVRieazPxN7xrpH1HBcbQWA/1FYk1gRn1vy6Xe3s=";
      };
    in
    {
      base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
      enable = true;
      image = wallpaper;
      polarity = "dark";

      cursor = {
        package = pkgs.material-cursors;
        name = "material_light_cursors";
      };

      fonts = {
        serif = {
          package = (pkgs.nerdfonts.override { fonts = [ "FiraCode" "Hack" "JetBrainsMono" ]; });
          name = "FiraCode Nerd Font Mono";
        };

        sansSerif = {
          package = (pkgs.nerdfonts.override { fonts = [ "FiraCode" "Hack" "JetBrainsMono" ]; });
          name = "FiraCode Nerd Font Mono";
        };

        monospace = {
          package = (pkgs.nerdfonts.override { fonts = [ "FiraCode" "Hack" "JetBrainsMono" ]; });
          name = "FiraCode Nerd Font Mono";
        };

        emoji = {
          package = pkgs.noto-fonts-emoji;
          name = "Noto Color Emoji";
        };
      };

      opacity = {
        desktop = 0.0;
        terminal = 0.9;
      };

      targets = {
        nixvim = {
          transparentBackground = {
            main = true;
            signColumn = true;
          };
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

  time.timeZone = "Europe/London";

  users = {
    users = {
      ali = {
        autoSubUidGidRange = true;
        isNormalUser = true;
        description = "Alison Jenkins";
        extraGroups = [ "networkmanager" "wheel" "docker" ];
        hashedPasswordFile = "/persistence/passwords/ali";
      };
      root = {
        hashedPasswordFile = "/persistence/passwords/root";
      };
    };
  };

  virtualisation = {
    docker = {
      enable = false;
    };

    libvirtd = {
      enable = true;
      qemu.swtpm.enable = true;
      qemu.ovmf = {
        enable = true;
        packages = [ pkgs.OVMFFull.fd ];
      };
    };
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
  };

  zramSwap = {
    enable = true;
  };
}

