{ inputs
, outputs
, pkgs
, ...
}: {
  imports = [
    (import ../../modules/locale { })
    ./disko-config.nix
    ./hardware-configuration.nix
  ];

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
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

  networking.hostName = "dev-vm";
  networking.networkmanager.enable = false;

  time.timeZone = "Europe/London";

  services.xserver = {
    enable = true;
    videoDrivers = [ "qxl" ];
    xkb = {
      layout = "us";
      variant = "";
    };
  };

  services.spice-vdagentd.enable = true;

  hardware.graphics = {
    enable = true;
  };

  console.keyMap = "us";

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  environment.pathsToLink = [ "/share/zsh" ];
  environment.variables = {
    NIXOS_OZONE_WL = "1";
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
    extraGroups = [ "networkmanager" "wheel" "docker" ];
  };

  nixpkgs = {
    config.allowUnfree = true;
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
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  system.stateVersion = "24.05";

  nix = {
    package = pkgs.nixVersions.stable;
    extraOptions = "experimental-features = nix-command flakes";
  };
}
