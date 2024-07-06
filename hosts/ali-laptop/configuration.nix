{
  outputs,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../app-profiles/desktop
    ../../app-profiles/hardware/touchpad
  ];

  boot = {
    kernelPackages = pkgs.linuxPackages_cachyos;
    loader = {
      efi.efiSysMountPoint = "/boot";
      grub = {
        enable = true;
        devices = ["nodev"];
        efiInstallAsRemovable = true;
        efiSupport = true;
        useOSProber = true;
        theme = pkgs.stdenv.mkDerivation {
          pname = "distro-grub-themes";
          version = "3.1";
          src = pkgs.fetchFromGitHub {
            owner = "AdisonCavani";
            repo = "distro-grub-themes";
            rev = "v3.1";
            hash = "sha256-ZcoGbbOMDDwjLhsvs77C7G7vINQnprdfI37a9ccrmPs=";
          };
          installPhase = "cp -r customize/nixos $out";
        };
      };
    };
  };

  networking.hostName = "ali-laptop";
  networking.networkmanager.enable = true;
  networking.extraHosts = ''
    192.168.1.202 home-kvm-hypervisor-1
  '';

  time.timeZone = "Europe/London";
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

  services.xserver = {
    videoDrivers = [
      "fbdev"
      "intel"
      "modesetting"
      "nvidia"
    ];
    xkb = {
      layout = "us";
      variant = "";
    };
  };

  hardware.graphics = {
    enable = true;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    nvidiaSettings = true;
    open = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    powerManagement = {
      enable = true;
      finegrained = false;
    };

    prime = {
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";

      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
    };
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  console.keyMap = "us";

  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  environment.pathsToLink = ["/share/zsh"];
  environment.variables = {
    NIXOS_OZONE_WL = "1";
    PATH = [
      "\${HOME}/.local/bin"
      "\${HOME}/.config/rofi/scripts"
    ];
    ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
  };

  programs.zsh.enable = true;

  users.users.ali = {
    isNormalUser = true;
    description = "Alison Jenkins";
    initialPassword = "initPw!";
    extraGroups = ["networkmanager" "wheel" "docker"];
    packages = with pkgs; [
      firefox
      neofetch
      lolcat
    ];
  };

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.master-packages
      outputs.overlays.modifications
      outputs.overlays.stable-packages
    ];
    config = {
      allowUnfree = true;
      permittedInsecurePackages = pkgs.lib.optional (pkgs.obsidian.version == "1.4.16") "electron-25.9.0";
    };
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 60d";
  };

  system.autoUpgrade = {
    enable = true;
    channel = "https://nixos.org/channels/nixos-23.11";
  };

  system.stateVersion = "23.11";

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = "experimental-features = nix-command flakes";
  };
}
