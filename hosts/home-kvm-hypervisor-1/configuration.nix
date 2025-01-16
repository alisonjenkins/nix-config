{ pkgs
, inputs
, outputs
, ...
}: {
  imports = [
    # ../../app-profiles/server-base/luks-tor-unlock
    (import ../../modules/locale { default_locale = "en_GB.UTF-8"; })
    ../../app-profiles/kvm-server
    ../../app-profiles/server-base
    ./hardware-configuration.nix
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
        devices = [ "nodev" ];
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

  console.keyMap = "us";
  environment.pathsToLink = [ "/share/zsh" ];
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
    extraGroups = [ "docker" "libvirtd" "networkmanager" "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF" ];
  };

  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      inputs.nur.overlays.default
      inputs.rust-overlay.overlays.default
      outputs.overlays.additions
      outputs.overlays.bacon-nextest
      outputs.overlays.master-packages
      outputs.overlays.modifications
      outputs.overlays.stable-packages
      outputs.overlays.tmux-sessionizer
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 60d";
  };

  system.stateVersion = "24.05";

  nix = {
    extraOptions = "experimental-features = nix-command flakes";
    package = pkgs.nixVersions.stable;
    settings = {
      auto-optimise-store = false;
      trusted-users = [ "root" "@wheel" ];
    };
  };

  security = {
    sudo = {
      wheelNeedsPassword = false;
    };
  };
}
