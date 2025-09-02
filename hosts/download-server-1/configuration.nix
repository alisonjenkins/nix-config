{ config
, inputs
, lib
, outputs
, pkgs
, ...
}: {
  imports = [
    (import ../../modules/locale { })
    ../../app-profiles/server-base
    (import ../../modules/base {
      enableImpermanence = true;
      inherit inputs lib pkgs;
    })
    # ../../app-profiles/server-base/luks-tor-unlock
    ../../app-profiles/storage-server
    ./hardware-configuration.nix
  ];

  console.keyMap = "us";
  programs.zsh.enable = true;
  time.timeZone = "Europe/London";

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      "irqpoll"
    ];
  };

  environment = {
    pathsToLink = [ "/share/zsh" ];

    systemPackages = with pkgs; [
      cifs-utils
      privoxy
      qbittorrent
      qbittorrent-cli
      radarr
      sonarr
      wireguard-tools
    ];

    variables = {
      PATH = [
        "\${HOME}/.local/bin"
        "\${HOME}/.config/rofi/scripts"
      ];
    };
  };

  networking = {
    hostName = "download-server-1";
    networkmanager.enable = true;

    firewall = {
      enable = true;
      allowPing = true;

      allowedTCPPorts = [
        22
        8118
      ];
      allowedUDPPorts = [];
    };
  };

  nix = {
    package = pkgs.nixVersions.stable;

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

  nixpkgs = {
    overlays = [
      # outputs.overlays.alvr
      inputs.nur.overlays.default
      inputs.rust-overlay.overlays.default
      outputs.overlays.additions
      outputs.overlays.bluray-playback
      outputs.overlays.master-packages
      outputs.overlays.modifications
      outputs.overlays.quirc
      outputs.overlays.snapper
      outputs.overlays.stable-packages
      outputs.overlays.tmux-sessionizer
    ];

    config.allowUnfree = true;
  };

  services = {
    logrotate.checkConfig = false;

    bazarr = {
      enable = false;
      openFirewall = true;
    };

    jellyseerr = {
      enable = false;
    };

    radarr = {
      enable = false;
      openFirewall = true;
    };

    sonarr = {
      enable = false;
      openFirewall = true;
    };

    qbittorrent = {
      enable = true;
      openFirewall = true;
    };

    privoxy = {
      enable = false;
      enableTor = true;

      settings = {
        listen-address = "0.0.0.0:8118";
        forward-socks5 = ".onion localhost:9050 .";
      };
    };
  };

  # sops = {
  #   defaultSopsFile = ../../secrets/main.enc.yaml;
  #   defaultSopsFormat = "yaml";
  #   age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  #   secrets = {
  #     # "myservice/my_subdir/my_secret" = {
  #     #   mode = "0400";
  #     #   owner = config.users.users.nobody.name;
  #     #   group = config.users.users.nobody.group;
  #     #   restartUnits = ["example.service"];
  #     #   path = "/a/secret/path.yaml";
  #     #   format = "yaml"; # can be yaml, json, ini, dotenv, binary
  # #     # };
  # #     # home_enc_key = {
  # #     #   format = "binary";
  # #     #   group = config.users.users.nobody.group;
  # #     #   mode = "0400";
  # #     #   neededForUsers = true;
  # #     #   owner = config.users.users.root.name;
  # #     #   path = "/etc/luks/home.key";
  # #     #   sopsFile = ../../secrets/ali-desktop/home-enc-key.enc.bin;
  # #     # };
  #   };
  # };

  system = {
    stateVersion = "24.05";
  };

  security = {
    sudo-rs = {
      wheelNeedsPassword = lib.mkForce false;
    };
  };

  users = {
    users = {
      ali = {
        description = "Alison Jenkins";
        extraGroups = [ "docker" "networkmanager" "wheel" ];
        # hashedPasswordFile = config.sops.secrets.ali.path;
        # hashedPasswordFile = "/persistence/passwords/ali";
        initialPassword = "initPw!";
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF" ];
      };
      root = {
        hashedPasswordFile = "/persistence/passwords/root";
      };
    };
  };
}
