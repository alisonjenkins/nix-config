{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../app-profiles/server-base
    # ../../app-profiles/server-base/luks-tor-unlock
    ../../app-profiles/kvm-server
  ];

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      "vfio-pci.ids=1000:0072"
      "systemd.gpt_auto=no"
    ];
    initrd = {
      availableKernelModules = [
        "ixgbe"
        "mt7921e"
        "r8169"
      ];
    };
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

  networking.hostName = "home-kvm-hypervisor-1";
  networking.networkmanager.enable = true;

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

  console.keyMap = "us";
  environment.pathsToLink = ["/share/zsh"];
  environment.variables = {
    PATH = [
      "\${HOME}/.local/bin"
      "\${HOME}/.config/rofi/scripts"
    ];
  };

  programs.zsh.enable = true;

  users.users.ali = {
    isNormalUser = true;
    description = "Alison Jenkins";
    initialPassword = "initPw!";
    extraGroups = ["docker" "libvirtd" "networkmanager" "wheel"];
    packages = with pkgs; [];
    openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF"];
  };

  nixpkgs.config.allowUnfree = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 60d";
  };

  system.autoUpgrade = {
    enable = true;
    channel = "https://nixos.org/channels/nixos-24.05";
  };

  system.stateVersion = "23.11";

  nix = {
    extraOptions = "experimental-features = nix-command flakes";
    package = pkgs.nixFlakes;
    settings = {
      auto-optimise-store = true;
      trusted-users = ["root" "@wheel"];
    };
  };

  security = {
    sudo = {
      wheelNeedsPassword = false;
    };
  };
}
