{ modulesPath
, lib
, pkgs
, inputs
, system
, outputs
, ...
}:
{
  imports = [
    (import ../../modules/locale { })
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    (import ../../modules/base {
      enableImpermanence = false;
      enablePlymouth = false;
      inherit inputs lib pkgs outputs;
    })
    ./disk-config.nix
  ];

  boot.initrd.kernelModules = [ "amdgpu" ];

  hardware.graphics.enable = true;

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
  ];

  networking = {
    hostName = "home-k8s-master-1";

    firewall = {
      enable = false;

      allowedTCPPorts = [
        6443
      ];

      extraCommands = ''
        iptables -I INPUT -d 192.168.1.240/28 -p tcp -m multiport --dports 80,443 -j ACCEPT
      '';
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
      wheelNeedsPassword = lib.mkForce false;
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
        "--disable-network-policy"
        "--disable=servicelb"
        "--flannel-backend=none"
        "--service-cidr=10.43.0.0/16"
        "--write-kubeconfig-mode \"0400\""
        # "--disable servicelb"
        # "--disable traefik"
        # "--disable-kube-proxy"
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
