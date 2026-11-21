{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  # The k3s join token lives here. Until the file is added (it needs this
  # host's age key in .sops.yaml), k3s and sops stay off so the host still
  # evaluates and builds.
  secretsFile = self + "/secrets/home-k8s-server-1/secrets.yaml";
  hasSecrets = builtins.pathExists secretsFile;
  # Flip to true only once sbctl keys exist at /var/lib/sbctl on the box
  # (runbook step 4 in docs/home-k8s-server-1.md). Lanzaboote cannot
  # install the bootloader without them, so the first install uses
  # systemd-boot.
  secureBootReady = false;
  # The OS sees no TPM on this unit (no fTPM even on BIOS FLT2.0.46.06.00).
  # Without one, tpm2-device=auto makes the initrd wait for a token before
  # asking for the passphrase. Flip to true once /dev/tpmrm0 exists (runbook
  # step 1 in docs/home-k8s-server-1.md).
  hasTpm = false;
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
      self.nixosModules.initrd-ssh
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
          bootLoader = if secureBootReady then "secure-boot" else "systemd-boot";
          # TODO: set from `systemd-analyze pcrs 15 --json=short` after the
          # first boot with Secure Boot enforced (runbook step 7). null skips
          # the check-pcrs unit.
          pcr15Value = null;
        };
        # TPM2 LUKS unlock: adds tpm2-device=auto (and PCR 15 measurement)
        # to crypttab. Forced because bootLoader = "secure-boot" turns it on
        # unconditionally. No TPM token is enrolled until the runbook's
        # systemd-cryptenroll step; until then the passphrase prompt (local
        # or initrd-ssh) unlocks the disk.
        systemIdentity.enable = lib.mkForce hasTpm;
        # Server profile; see ADR 0057.
        modules.kernelTuning.profiles = [ "hardened-server" ];
        modules.locale.enable = true;
        modules.servers.enable = true;

        console.keyMap = "us";
        networking.hostName = "home-k8s-server-1";
        networking.networkmanager.enable = true;
        # Same as home-k8s-master-1: Cilium (host firewall, kube-proxy
        # replacement) owns packet filtering on cluster nodes, and the NixOS
        # firewall would drop VXLAN, health checks and NodePorts. While k3s is
        # off (no secrets yet) nothing else filters, so keep the firewall on.
        networking.firewall.enable = !hasSecrets;

        # Worker node for home-cluster-1. An agent, not a second server: a
        # two-member embedded etcd loses quorum when either node goes down,
        # which is worse than the single control plane on master-1.
        # serverAddr is an IP so joining never depends on LAN DNS, which this
        # node will itself be serving.
        services.openssh.enable = true;
        services.k3s = {
          enable = hasSecrets;
          role = "agent";
          serverAddr = "https://${outputs.lib.homeLan.hosts.home-k8s-master-1.ip}:6443";
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
        boot.kernel.sysctl = lib.mkIf hasSecrets {
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
        # Remote LUKS unlock: the box is headless, so a boot that stops at
        # the passphrase prompt is answered over SSH on port 2222 with
        # `systemd-tty-ask-password-agent`. The initrd gets its address by
        # DHCP on eno1 (igb, loaded from hardware-configuration.nix).
        modules.initrd-ssh = {
          enable = true;
          authorizedKeys = [ outputs.lib.sshKeys.primary ];
          hostKeyComment = "home-k8s-server-1-initrd";
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
          # Required by modules.initrd-ssh.
          initrd.systemd.enable = true;
          # Bypass kernel workqueues for dm-crypt: lower latency on
          # the SATA SSD. Runtime-only, applies on next boot.
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
