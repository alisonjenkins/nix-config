{ lib
, inputs
, outputs
, pkgs
, ...
}: {
  imports = [
    (import ../../modules/locale { })
    (import ../../modules/libvirtd { inherit pkgs; })
    (import ../../modules/base {
      enableImpermanence = true;
      impermanencePersistencePath = builtins.toPath "/persistence";
      inherit inputs lib;
    })
    (import ../../modules/desktop {
      inherit inputs pkgs lib;
    })
    (import ../../modules/vr { enableOpenSourceVR = false; })
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
    # kernelPackages = pkgs.linuxPackages_cachyos;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_latest;
    # kernelPackages = pkgs.linuxPackages_xanmod;
    # kernelPackages = pkgs.linuxPackages_zen;
    kernelPackages = pkgs.linuxPackages_cachyos-lto;

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
      clinfo
      framework-tool
      ldacbt
      qmk
      qmk-udev-rules
      qmk_hid
      rocmPackages.rocminfo
      sbctl
      tpm2-tss
    ];
  };

  hardware = {
    enableRedistributableFirmware = true;
    keyboard.qmk.enable = true;
    wirelessRegulatoryDatabase = true;

    graphics = {
      enable = true;
      enable32Bit = true;

      extraPackages = with pkgs; [ rocmPackages.clr.icd ];
    };

    amdgpu = {
      initrd = {
        enable = true;
      };

      opencl = {
        enable = true;
      };
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

    ollama = {
      enable = true;
      acceleration = "rocm";
      rocmOverrideGfx = "11.0.2";
      user = "ollama";
      group = "ollama";
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
      enable = false;
    };
  };
}
