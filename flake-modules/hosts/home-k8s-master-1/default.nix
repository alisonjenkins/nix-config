{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
in {
  flake.nixosConfigurations.home-k8s-master-1 = lib.nixosSystem {
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
      self.nixosModules.home-k8s-master-1-hardware
      self.nixosModules.home-k8s-master-1-disko-config

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops

      # Host-specific configuration
      ({ modulesPath, lib, outputs, pkgs, ... }: {
        imports = [
          (modulesPath + "/installer/scan/not-detected.nix")
          (modulesPath + "/profiles/qemu-guest.nix")
        ];

        modules.nohang = {
          enable = true;
          extraProtectedProcesses = [ "k3s" "containerd" ];
        };
        modules.base = {
          enable = true;
        };
        modules.locale.enable = true;

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
                #   source = self + "/k8s-setup/cilium-hr.yaml";
                # };
              };
          };
        };

        sops = {
          defaultSopsFile = self + "/secrets/home-k8s-master-1/secrets.yaml";
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
              sopsFile = self + "/secrets/home-k8s-master-1/secrets.yaml";
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
              outputs.lib.sshKeys.primary
            ];
          };
      })
    ];
  };
}
