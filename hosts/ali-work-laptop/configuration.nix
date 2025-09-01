{ config
, lib
, inputs
, outputs
, pkgs
, ...
}: {
  imports = [
    # ../../app-profiles/desktop
    (import ../../modules/locale { })
    ../../app-profiles/hardware/touchpad
    ./hardware-configuration.nix
  ];

  boot = {
    kernelPackages = pkgs.linuxPackages_testing;
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
      NIXOS_OZONE_WL = "1";
      PATH = [
        "\${HOME}/.local/bin"
        "\${HOME}/.config/rofi/scripts"
      ];
      ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
    };
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
      inputs.nur.overlays.default
      inputs.rust-overlay.overlays.default
      outputs.overlays.additions
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

  security.rtkit.enable = true;

  services = {
    auto-cpufreq = {
      enable = true;

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

    pulseaudio = {
      enable = false;
    };

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    power-profiles-daemon.enable = lib.mkForce false;

    thermald = {
      enable = true;
    };

    tlp = {
      enable = false;
      settings = {
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

        CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

        CPU_MIN_PERF_ON_AC = 0;
        CPU_MAX_PERF_ON_AC = 100;
        CPU_MIN_PERF_ON_BAT = 0;
        CPU_MAX_PERF_ON_BAT = 20;

        #Optional helps save long term battery health
        START_CHARGE_THRESH_BAT0 = 40; # below this percentage it starts to charge
        STOP_CHARGE_THRESH_BAT0 = 95; # above this percentage it stops charging
      };
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
          package = pkgs.nerd-fonts.fira-code;
          name = "FiraCode Nerd Font Mono";
        };

        sansSerif = {
          package = pkgs.nerd-fonts.fira-code;
          name = "FiraCode Nerd Font Mono";
        };

        monospace = {
          package = pkgs.nerd-fonts.fira-code;
          name = "FiraCode Nerd Font Mono";
        };

        emoji = {
          package = pkgs.noto-fonts-color-emoji;
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

  system = {
    stateVersion = "24.05";
  };

  time.timeZone = "Europe/London";

  users = {
    users = {
      ali = {
        isNormalUser = true;
        description = "Alison Jenkins";
        initialPassword = "initPw!";
        extraGroups = [ "networkmanager" "wheel" "docker" ];
      };
    };
  };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
  };
}
