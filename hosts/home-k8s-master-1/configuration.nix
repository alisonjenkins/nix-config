{ modulesPath
, lib
, pkgs
, inputs
, system
, ...
}:
{
  imports = [
    (import ../../modules/locale { })
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
  ];

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  environment.systemPackages = map lib.lowPrio [
    inputs.ali-neovim.packages.${system}.nvim
    pkgs.curl
    pkgs.gitMinimal
    pkgs.htop
  ];

  networking = {
    hostName = "home-k8s-master-1";

    firewall = {
      enable = true;

      allowedTCPPorts = [
        6443
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
        "--cluster-cidr=10.42.0.0/16"
        "--cluster-init"
        # "--disable servicelb"
        # "--disable traefik"
        # "--disable-kube-proxy"
        # "--disable-network-policy"
        # "--flannel-backend=none"
        "--service-cidr=10.43.0.0/16"
        "--write-kubeconfig-mode \"0400\""
      ];

      manifests =
        {
          # cilium = {
          #   source = ../../k8s-setup/cilium-hr.yaml;
          # };
        };
    };
  };

  sops = {
    defaultSopsFile = ../../secrets/home-k8s-master-1/secrets.yaml;
    defaultSopsFormat = "yaml";

    age = {
      # generateKey = true;
      # keyFile = "/var/lib/sops-nix/key.txt";
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };

    secrets = {
      k8s-token = {
        group = "root";
        mode = "0400";
        owner = "root";
        path = "/run/secrets/k8s-token";
        restartUnits = [ "k3s.service" ];
        sopsFile = ../../secrets/home-k8s-master-1/secrets.yaml;
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
