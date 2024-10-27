{ modulesPath
, lib
, pkgs
, inputs
, system
, ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
  ];

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    inputs.ali-neovim.packages.${system}.nvim
  ];

  networking = {
    firewall.allowedTCPPorts = [
      6443
    ];
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

  security = {
    sudo = {
      wheelNeedsPassword = false;
    };
  };

  services = {
    openssh = {
      enable = true;
    };

    k3s = {
      enable = true;
      role = "server";
      tokenFile = "/run/secrets/k8s-token";
      extraFlags = toString [
        "--write-kubeconfig-mode \"0400\""
        "--cluster-init"
        "--disable servicelb"
        "--disable traefik"
      ];
    };
  };

  sops = {
    defaultSopsFile = ../../secrets/home-k8s-master-1/secrets.yaml;
    defaultSopsFormat = "yaml";

    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = true;
    };

    secrets = {
      k8s-token = {
        sopsFile = ../../secrets/home-k8s-master-1/secrets.yaml;
        mode = "0400";
        owner = "root";
        group = "root";
        path = "/run/secrets/k8s-token";
        restartUnits = [ "k3s.service" ];
      };
    };
  };

  system.stateVersion = "24.05";

  users.users.ali =
    {
      isNormalUser = true;
      description = "Alison Jenkins";
      initialPassword = "initPw!";
      extraGroups = [ "networkmanager" "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqNVcWqkNPa04xMXls78lODJ21W43ZX6NlOtFENYUGF"
      ];
    };
}
