{ lib
, inputs
, outputs
, pkgs
, ...
}: {
  imports = [
    ../../app-profiles/desktop
    ../../app-profiles/desktop/kwallet
    ../../app-profiles/hardware/touchpad
    ./disko-config.nix
    ./hardware-configuration.nix

    (import ../../modules/ollama)
    (import ../../app-profiles/hardware/fingerprint-reader { username = "ali"; })
    (import ../../modules/locale { })
    (import ../../modules/libvirtd { inherit pkgs; })
    (import ../../modules/printing { inherit pkgs; })

    (import ../../modules/desktop {
      inherit inputs pkgs lib;
      pipeWireQuantum = 512;
    })
    (import ../../modules/base {
      enableImpermanence = true;
      impermanencePersistencePath = builtins.toPath "/persistence";
      pcr15Value = "2ed3e75741c65cda190d143376c463c88557e8d7ab53f8dfe788a263aaec50b7";
      useSecureBoot = true;
      useSystemdBoot = false;
      inherit inputs lib outputs pkgs;
    })
  ];

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;

    extraModprobeConfig = ''
      options snd-hda-intel index=1,0
    '';

    kernelParams = [
      "amd_iommu=off"
    ];

    kernelPatches = [
      {
        name = "amd-isp-capture";
        patch = (pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/nekinie/linux-g1a/refs/heads/main/990-amd-isp-capture.patch";
          hash = "sha256-hzvVdSbcYCzXNXvItins4inOL44ukMhSDgw6Pea1Dlw=";
        });
      }
      {
        name = "amd-ll-isp4";
        patch = (pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/nekinie/linux-g1a/refs/heads/main/991-amd-ll-isp4.patch";
          hash = "sha256-DPBtLkjuQdjT3gfL96gsIs2+jt6y6OZ2TWgv3DQ8u7A=";
        });
      }
      {
        name = "isp4-fw-hw-interface";
        patch = (pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/nekinie/linux-g1a/refs/heads/main/992-isp4-fw-hw-interface.patch";
          hash = "sha256-9mIW23NQ4qOpl1HZ7JESHZiDqCNSZY1QwbAlW0I5XNs=";
        });
      }
      {
        name = "isp4-firmware-loading";
        patch = (pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/nekinie/linux-g1a/refs/heads/main/993-isp4-firmware-loading.patch";
          hash = "sha256-VTRYyCQDhfB3iCWNp04w8NX7dTnJel2mDbxBBWGQ54k=";
        });
      }
      {
        name = "isp4-video-node";
        patch = (pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/nekinie/linux-g1a/refs/heads/main/994-isp4-video-node.patch";
          hash = "sha256-+K+9uIRMlo58xEyIBmyfNDdKYDPOTTxH7WaWoS7lVVo=";
        });
      }
      {
        name = "isp4-debug";
        patch = (pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/nekinie/linux-g1a/refs/heads/main/995-isp4-debug.patch";
          hash = "sha256-EQpkyNWDu+ghWKebmENgRwCjM8tB4pHuX4msmUna5Io=";
        });
      }
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
      wallpapers
    ];
  };

  hardware = {
    graphics.enable = true;
  };

  networking = {
    hostName = "ali-work-laptop";
    networkmanager.enable = true;
  };

  nix = {
    package = pkgs.nixVersions.stable;

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 60d";
    };
  };

  nixpkgs = {
    overlays = [
      inputs.niri-flake.overlays.niri
      inputs.nur.overlays.default
      inputs.rust-overlay.overlays.default
      outputs.overlays._1password-gui
      outputs.overlays.additions
      outputs.overlays.linux-firmware
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
    niri = {
      enable = true;
      package = pkgs.niri-unstable;
    };
  };

  security.rtkit.enable = true;

  services = {
    logind = {
      lidSwitch = "suspend-then-hibernate";
    };

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
      videoDrivers = [
        "fbdev"
        "modesetting"
      ];
      xkb = {
        layout = "us";
        variant = "";
      };
    };
  };

  system = {
    stateVersion = "24.05";
  };

  systemd = {
    sleep = {
      extraConfig = ''
        HibernateDelaySec=30m
        SuspendState=mem
      '';
    };
  };

  time.timeZone = "Europe/London";

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
}
