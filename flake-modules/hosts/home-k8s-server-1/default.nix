{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  # The k3s join token lives here. Until the file is added (it needs this
  # host's age key in .sops.yaml), k3s and sops stay off so the host still
  # evaluates and builds.
  secretsFile = self + "/secrets/home-k8s-server-1/secrets.yaml";
  hasSecrets = builtins.pathExists secretsFile;
in {
  flake.nixosConfigurations.home-k8s-server-1 = lib.nixosSystem {
    specialArgs = {
      username = "ali";
      inherit inputs;
      inherit (self) outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }

      # Custom modules via flake outputs
      self.nixosModules.locale
      self.nixosModules.base
      self.nixosModules.nohang
      self.nixosModules.servers
      self.nixosModules.home-k8s-server-1-hardware
      self.nixosModules.home-k8s-server-1-disko-config

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops

      # Host-specific configuration
      ({ lib, pkgs, outputs, ... }: {
        modules.nohang = {
          enable = true;
          extraProtectedProcesses = [ "k3s" "containerd" ];
        };
        modules.base = {
          enable = true;
        };
        # Server profile; see ADR 0057.
        modules.kernelTuning.profiles = [ "hardened-server" ];
        modules.locale.enable = true;
        modules.servers.enable = true;

        console.keyMap = "us";
        networking.hostName = "home-k8s-server-1";
        networking.networkmanager.enable = true;
        # Same as home-k8s-master-1: Cilium (host firewall, kube-proxy
        # replacement) owns packet filtering on cluster nodes, and the NixOS
        # firewall would drop VXLAN, health checks and NodePorts.
        networking.firewall.enable = false;

        # Worker node for home-cluster-1. An agent, not a second server: a
        # two-member embedded etcd loses quorum when either node goes down,
        # which is worse than the single control plane on master-1.
        # serverAddr is an IP so joining never depends on LAN DNS, which this
        # node will itself be serving.
        services.openssh.enable = true;
        services.k3s = {
          enable = hasSecrets;
          role = "agent";
          serverAddr = "https://192.168.1.129:6443";
          # Must match the server's version (see home-k8s-master-1).
          package = pkgs.unstable.k3s_1_34;
          tokenFile = "/run/secrets/k8s-token";
          extraFlags = toString [
            # CloudNativePG image volumes; matches the server's gate.
            "--kubelet-arg=feature-gates=ImageVolume=true"
          ];
        };

        # NFS client so kubelet can mount NFS PersistentVolumes.
        boot.supportedFilesystems = [ "nfs" ];

        # Cilium L7LB (Gateway API / Ingress) needs these to deliver
        # TPROXY-redirected packets to envoy (see home-k8s-master-1). Both
        # are OR'd with the per-interface value, so `all` covers the NIC
        # whatever its name.
        boot.kernel.sysctl = {
          "net.ipv4.conf.all.accept_local" = 1;
          "net.ipv4.conf.all.route_localnet" = 1;
        };

        # Cluster join token: the same value as home-k8s-master-1's k8s-token.
        sops = lib.mkIf hasSecrets {
          defaultSopsFile = secretsFile;
          defaultSopsFormat = "yaml";
          age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
          secrets.k8s-token = {
            group = "root";
            mode = "0400";
            owner = "root";
            path = "/run/secrets/k8s-token";
            restartUnits = [ "k3s.service" ];
          };
        };
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
          # Bypass kernel workqueues for dm-crypt — significant
          # I/O improvement on virtio-blk backed by host NVMe.
          # Runtime-only, applies on next boot.
          initrd.luks.devices.crypted.crypttabExtraOpts = [
            "no-read-workqueue"
            "no-write-workqueue"
          ];
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
          openssh.authorizedKeys.keys = [ outputs.lib.sshKeys.primary ];
        };
      })
    ];
  };
}
