{ config
, inputs
, lib
, outputs
, pkgs
, ...
}: {
  imports = [
    (import ../../modules/locale { })
    (import ../../modules/base {
      enableImpermanence = true;
      inherit inputs lib outputs pkgs;
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
      parted
      xfsprogs
    ];

    variables = {
      PATH = [
        "\${HOME}/.local/bin"
        "\${HOME}/.config/rofi/scripts"
      ];
    };
  };

  networking = {
    hostName = "home-storage-server-1";
    networkmanager.enable = true;

    firewall = {
      enable = true;
      allowPing = true;

      allowedTCPPorts = [
        22
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

  services = {
    logrotate.checkConfig = false;

    smartd = {
      enable = true;
      autodetect = true;
      notifications = {
        mail.enable = true;
        wall.enable = true;
      };
      defaults.monitored = "-a -o on -s (S/../.././02|L/../../6/03)";
    };

    samba = {
      enable = true;
      openFirewall = true;

      settings = {
        global = {
          "aio read size" = "16384";
          "aio write size" = "16384";
          "getwd cache" = "yes";
          "oplocks" = "yes";
          "read raw" = "yes";
          "socket options" = "TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072";
          "use sendfile" = "yes";
          "write raw" = "yes";
        };

        "storage" = {
          path = "/media/storage";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "ali";
        };

        "k8s-storage" = {
          path = "/media/storage/k8s-storage";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "privoxy";
        };

        "media" = {
          path = "/media/storage/media";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "ali jellyfin";
        };

        "movies" = {
          path = "/media/storage/media/Movies";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "ali radarr";
        };

        "tv" = {
          path = "/media/storage/media/TV";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "ali sonarr";
        };

        "downloads" = {
          path = "/media/storage/downloads";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "download-server";
        };
      };
    };

    samba-wsdd = {
      enable = true;
      openFirewall = true;
    };

    snapraid = let
      dataDisks = lib.attrsets.filterAttrs (mountPoint: diskOptions:
        lib.strings.hasPrefix "/media/disks" mountPoint
      ) config.fileSystems;

      parityDisks = lib.attrsets.filterAttrs (mountPoint: diskOptions:
        lib.strings.hasPrefix "/media/parity" mountPoint
      ) config.fileSystems;

      contentFilesOpt = lib.lists.map (item: "${item}/snapraid.content") ((builtins.attrNames dataDisks) ++ (builtins.attrNames parityDisks));
      parityFilesOpt = lib.lists.map (item: "${item}/snapraid.parity") (builtins.attrNames parityDisks);

      dataDisksOpt = builtins.map (mountPoint:
        let
          diskName = lib.strings.replaceStrings ["/media/disks/"] [""] mountPoint;
        in
        {
          name = diskName;
          value = mountPoint;
        }
      ) (builtins.attrNames dataDisks);
    in {
      # Disable SnapRAID in VM since we don't have the complex disk setup
      enable = !config.system.isVM;

      contentFiles = contentFilesOpt;
      dataDisks = (builtins.listToAttrs dataDisksOpt);
      parityFiles = parityFilesOpt;
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
    sudo = {
      wheelNeedsPassword = lib.mkForce false;
    };
  };

  users = {
    groups = {
      download-server = {};
      jellyfin = {};
      privoxy = {};
      radarr = {};
      sonarr = {};
    };

    users = {
      ali = {
        description = "Alison Jenkins";
        extraGroups = [ "docker" "networkmanager" "wheel" ];
        # hashedPasswordFile = config.sops.secrets.ali.path;
        hashedPasswordFile = "/persistence/passwords/ali";
        # initialPassword = "initPw!";
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF" ];
      };
      download-server = {
        description = "Download Server user";
        group = "download-server";
        hashedPasswordFile = "/persistence/passwords/download-server";
        isNormalUser = true;
      };
      radarr = {
        description = "Radarr user";
        group = "radarr";
        hashedPasswordFile = "/persistence/passwords/radarr";
        isNormalUser = true;
      };
      sonarr = {
        description = "Sonarr user";
        group = "sonarr";
        hashedPasswordFile = "/persistence/passwords/sonarr";
        isNormalUser = true;
      };
      jellyfin = {
        description = "Jellyfin user";
        group = "jellyfin";
        hashedPasswordFile = "/persistence/passwords/jellyfin";
        isNormalUser = true;
      };
      privoxy = {
        description = "Privoxy user";
        group = "privoxy";
        hashedPasswordFile = "/persistence/passwords/privoxy";
        isNormalUser = true;
      };
      root = {
        hashedPasswordFile = "/persistence/passwords/root";
      };
    };
  };
}
