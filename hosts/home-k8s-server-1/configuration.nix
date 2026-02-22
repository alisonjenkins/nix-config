{
  inputs,
  lib,
  pkgs,
  outputs,
  ...
}: {
  imports = [
    # ../../app-profiles/server-base/luks-tor-unlock
    ../../modules/locale
    ../../app-profiles/k8s-master
    ./hardware-configuration.nix
    ../../modules/base
    ../../modules/servers
  ];

  modules.base = {
    enable = true;
    enablePlymouth = false;
  };
  modules.locale.enable = true;
  modules.servers.enable = true;

  console.keyMap = "us";
  networking.hostName = "home-k8s-server-1";
  networking.networkmanager.enable = true;
  programs.zsh.enable = true;
  services.logrotate.checkConfig = false;
  time.timeZone = "Europe/London";

  boot = {
    kernelPackages = pkgs.linuxPackages;
    kernelParams = [
      "irqpoll"
    ];
    loader = {
      efi = {
        efiSysMountPoint = "/boot";
        canTouchEfiVariables = true;
      };
    };
  };

  environment = {
    pathsToLink = [ "/share/zsh" ];

    systemPackages = with pkgs; [
      parted
    ];

    variables = {
      PATH = [
        "\${HOME}/.local/bin"
        "\${HOME}/.config/rofi/scripts"
      ];
    };
  };

  nix = {
    package = pkgs.nixVersions.stable;
    extraOptions = "experimental-features = nix-command flakes";

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

  system = {
    stateVersion = "24.05";
  };

  security = {
    sudo = {
      wheelNeedsPassword = lib.mkForce false;
    };
  };

  users.users.ali = {
    isNormalUser = true;
    description = "Alison Jenkins";
    initialPassword = "initPw!";
    extraGroups = [ "docker" "networkmanager" "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF" ];
  };
}
