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
        2049  # NFS
        111   # RPC
      ];
      allowedUDPPorts = [
        2049  # NFS
        111   # RPC
      ];
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

  # Set proper ownership and permissions on media directories
  systemd.tmpfiles.rules = [
    # Downloads directory: owner=qbittorrent, group=media, setgid bit
    "d /media/storage/downloads 2775 qbittorrent media -"
    "d /media/storage/downloads/downloading 2775 qbittorrent media -"
    "d /media/storage/downloads/complete 2775 qbittorrent media -"

    # Movies directory: owner=radarr, group=movies
    "d /media/storage/media/Movies 2775 radarr movies -"

    # TV directory: owner=sonarr, group=tv
    "d /media/storage/media/TV 2775 sonarr tv -"
  ];

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

    # NFS Server - runs alongside Samba for performance comparison
    nfs.server = {
      enable = true;
      # Lock to NFSv4 only for better performance and security
      lockdPort = 4001;
      mountdPort = 4002;
      statdPort = 4000;

      exports = ''
        # Downloads share - optimized for qBittorrent on download-server
        # no_root_squash: Allow root access from client
        # no_subtree_check: Better performance, safe for dedicated exports
        # sync: Ensure data integrity on server (client uses async for speed)
        /media/storage/downloads    192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=1)

        # Movies share - for Radarr
        /media/storage/media/Movies 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=2)

        # TV share - for Sonarr
        /media/storage/media/TV     192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=3)
      '';
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
      # Fixed GIDs to match download-server-1
      download-server = { gid = 5004; };
      games = { gid = 5014; };
      jellyfin = { gid = 5005; };
      media = { gid = 5000; };  # Shared group for all media services
      movies = { gid = 5011; };
      music = { gid = 5012; };
      privoxy = { gid = 5006; };
      qbittorrent = { gid = 5001; };  # Add qbittorrent group to match download server
      radarr = { gid = 5002; };
      sonarr = { gid = 5003; };
      tv = { gid = 5013; };
    };

    users = {
      ali = {
        description = "Alison Jenkins";
        extraGroups = [
          "docker"
          "games"
          "movies"
          "music"
          "networkmanager"
          "tv"
          "wheel"
        ];
        # hashedPasswordFile = config.sops.secrets.ali.path;
        hashedPasswordFile = "/persistence/passwords/ali";
        # initialPassword = "initPw!";
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF" ];
      };
      download-server = {
        description = "Download Server user";
        group = "download-server";
        uid = 5004;
        hashedPasswordFile = "/persistence/passwords/download-server";
        isNormalUser = true;
      };
      # Add qbittorrent user to match download server
      qbittorrent = {
        description = "qBittorrent user";
        group = "qbittorrent";
        uid = 5001;
        extraGroups = ["media"];  # Add to shared media group
        home = "/var/lib/qBittorrent";
        createHome = false;
        isSystemUser = true;
      };
      radarr = {
        description = "Radarr user";
        group = "radarr";
        uid = 5002;
        extraGroups = ["media" "movies"];  # Add to shared media group
        hashedPasswordFile = "/persistence/passwords/radarr";
        isNormalUser = true;
      };
      sonarr = {
        description = "Sonarr user";
        group = "sonarr";
        uid = 5003;
        extraGroups = ["media" "tv"];  # Add to shared media group
        hashedPasswordFile = "/persistence/passwords/sonarr";
        isNormalUser = true;
      };
      jellyfin = {
        description = "Jellyfin user";
        group = "jellyfin";
        uid = 5005;
        extraGroups = ["media" "movies" "tv" "music"];  # Add to shared media group
        hashedPasswordFile = "/persistence/passwords/jellyfin";
        isNormalUser = true;
      };
      privoxy = {
        description = "Privoxy user";
        group = "privoxy";
        uid = 5006;
        hashedPasswordFile = "/persistence/passwords/privoxy";
        isNormalUser = true;
      };
      root = {
        hashedPasswordFile = "/persistence/passwords/root";
      };
    };
  };
}
