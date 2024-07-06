{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../app-profiles/server-base
    ../../app-profiles/server-base/luks-tor-unlock
    ../../app-profiles/storage-server
  ];

  console.keyMap = "us";
  networking.hostName = "home-storage-server-1";
  networking.networkmanager.enable = true;
  nixpkgs.config.allowUnfree = true;
  programs.zsh.enable = true;
  services.logrotate.checkConfig = false;
  time.timeZone = "Europe/London";

  boot = {
    kernelPackages = pkgs.linuxPackages;
    kernelParams = [
      "irqpoll"
    ];
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

  environment = {
    pathsToLink = ["/share/zsh"];

    variables = {
      PATH = [
        "\${HOME}/.local/bin"
        "\${HOME}/.config/rofi/scripts"
      ];
    };
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

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = "experimental-features = nix-command flakes";

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 60d";
    };

    settings = {
      trusted-users = [ "root" "@wheel" ];
    };
  };

  system = {
    stateVersion = "23.11";

    autoUpgrade = {
      enable = true;
      channel = "https://nixos.org/channels/nixos-23.11";
    };
  };

  security = {
    sudo = {
      wheelNeedsPassword = false;
    };
  };

  users.users.ali = {
    isNormalUser = true;
    description = "Alison Jenkins";
    initialPassword = "initPw!";
    extraGroups = ["docker" "networkmanager" "wheel"];
    packages = with pkgs; [];
    openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF"];
  };
}
