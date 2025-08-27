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
    kernelPackages = pkgs.linuxPackages;
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

    samba = {
      enable = true;
      openFirewall = true;

      settings = {
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
      enable = true;

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
