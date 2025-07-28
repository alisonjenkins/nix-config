{ pkgs
, inputs
  # , lib
, ...
}: {
  imports = [
    inputs.lsfg-vk-flake.nixosModules.default
    inputs.stylix.nixosModules.stylix
  ];

  environment = {
    systemPackages = with pkgs; [
      deepfilternet
      file-roller
      hicolor-icon-theme
      inputs.caelestia-cli.packages.${system}.default
      pciutils
      playerctl
      powertop
      unstable.easyeffects
      unstable.mission-center
      unstable.nvtopPackages.amd
      wleave
    ];

    variables = {
      LSFG_DLL_PATH = "\${HOME}/.local/share/Steam/steamapps/common/Lossless\ Scaling/Lossless.dll";
      NIXOS_OZONE_WL = "1";
      ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
    };
  };

  hardware = {
    graphics = {
      enable = true;
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

  security = {
    polkit = {
      enable = true;
    };

    rtkit = {
      enable = true;
    };

    soteria = {
      enable = true;
    };
  };

  services = {
    ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };

    lsfg-vk = {
      enable = true;
    };

    pulseaudio = {
      enable = false;
    };

    pipewire = {
      alsa.enable = true;
      alsa.support32Bit = true;
      enable = true;
      jack.enable = true;
      pulse.enable = true;

      audio = {
        enable = true;
      };

      extraConfig = {
        pipewire = {
          "10-clock-rate" = {
            "context.properties" = {
              "default.clock.allowed-rates" = [44100 48000 88200 96000];
            };
          };
        };
      };

      wireplumber = {
        enable = true;
      };
    };

    power-profiles-daemon = {
      enable = false;
    };

    tlp = {
      enable = true;

      settings = {
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
        size = 30;
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

      homeManagerIntegration = {
        followSystem = true;
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

        qt = {
          enable = false;
        };
      };
    };

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
  };
}
