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
      self.nixosModules.nvidia-transcode
      self.nixosModules.home-k8s-master-1-hardware
      self.nixosModules.home-k8s-master-1-disko-config

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops

      # Host-specific configuration
      ({ config, modulesPath, lib, outputs, pkgs, ... }: {
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

        # NVENC transcode stack for the GTX 1070 passed through from
        # home-kvm-hypervisor-1 (modules.vfioIsolate there + the <hostdev> in
        # this VM's domain XML). Loading the proprietary driver with no GPU yet
        # present is benign — the kmod probes nothing and creates no /dev/nvidia*
        # — so this deploys safely before the card is seated. Pinned to the 580
        # `production` branch: 590 dropped Pascal (assertion enforces it).
        # Cluster-layer follow-ups (NOT node config): the `nvidia` RuntimeClass,
        # the nvidia-device-plugin DaemonSet advertising `nvidia.com/gpu`, and
        # the pharos Deployment's GPU resource request.
        #
        # Pinned to legacy_580 (580.173.02): the 1070 is Pascal, and the current
        # `production`/`stable` (595.x) dropped Pascal. legacy_580 is NVIDIA's
        # Pascal/Maxwell/Volta legacy-support branch (< 590, satisfies the
        # module's requirePascalDriver assertion).
        modules.nvidiaTranscode = {
          enable = true;
          driverPackage = config.boot.kernelPackages.nvidiaPackages.legacy_580;
          # Uncap concurrent NVENC sessions (byte-patches libnvidia-encode.so).
          # ON 2026-07-21: lifts the stock 5-session consumer cap so pharos'
          # NVENC probe can ramp to its full 8 permits on the 1070. Forces a
          # LOCAL driver rebuild (the patched .so is not in the binary cache).
          # Verified to patch 580.173.02 exactly once (see modules/nvidia-transcode).
          nvencUnlock = true;
        };

        # Discover GPUs via NVML directly instead of the default `auto` probe.
        # `auto` additionally sniffs for WSL/Tegra/CSV environments, which this
        # headless x86 passthrough node is not — `nvml` is the exact, minimal
        # mode for a normal discrete GPU and skips those pointless probes.
        # (extraArgs can't set this: it only appends a duplicate flag and
        # nvidia-ctk honours the first; `discovery-mode` is the replacing knob.)
        hardware.nvidia-container-toolkit.discovery-mode = "nvml";

        # Put nvidia-container-runtime on k3s' PATH so k3s' startup
        # auto-detection templates a `nvidia` containerd runtime (in the
        # correct config version for its bundled containerd). NixOS'
        # nvidia-container-toolkit installs the runtime into the store but not
        # onto k3s' (minimal) service PATH, so without this k3s never sees it:
        # the `nvidia` RuntimeClass resolves to a handler containerd doesn't
        # have, and a `runtimeClassName: nvidia` pod fails to start.
        # NB: the runtime binary lives in the package's `tools` OUTPUT (the
        # default output only ships nvidia-ctk), so getOutput "tools" — the
        # same reference the nixpkgs module uses for the runtime hook.
        systemd.services.k3s.path = [
          (lib.getOutput "tools" config.hardware.nvidia-container-toolkit.package)
        ];

        boot.initrd.kernelModules = [ "amdgpu" ];

        # NFS client (mount.nfs) so kubelet can mount NFS PersistentVolumes —
        # the Jellyfin media volume moved from SMB to NFS over the jumbo
        # br-storage path (10.10.10.2:/media/storage/media). Without this the
        # kernel supports nfs but the userspace mount helper is absent and
        # mounts fail with "mount program didn't pass remote address".
        boot.supportedFilesystems = [ "nfs" ];

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

          # Second (jumbo) NIC on br-storage, bound by its fixed MAC. Isolated
          # point-to-point with home-storage-server-1 (10.10.10.2), no gateway/DNS
          # — the directly-connected /24 carries the Jellyfin media NFS mount off
          # the LAN br0. MTU 9000 must match every hop. Same pattern as
          # download-server-1's storage-jumbo profile.
          networkmanager.ensureProfiles.profiles = {
            storage-jumbo = {
              connection = {
                id = "storage-jumbo";
                type = "ethernet";
                autoconnect = true;
              };
              ethernet = {
                mac-address = "52:54:00:0A:29:41";
                mtu = 9000;
              };
              ipv4 = {
                method = "manual";
                address1 = "10.10.10.3/24";
              };
              ipv6.method = "disabled";
            };
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
            # Bump to 1.34.7+k3s1 from nixpkgs_unstable (nixos-25.11 still
            # ships 1.34.5+k3s1). 1.34.5 self-shutdowns every 15 minutes on
            # "tunnel watches failed to wait for RBAC: context deadline
            # exceeded" — tunnel-server SelfSubjectAccessReview probe hits
            # its hard 15-minute HTTP timeout against the local apiserver.
            # Drop this override once nixos-25.11 picks up the bump.
            package = pkgs.unstable.k3s_1_34;
            tokenFile = "/run/secrets/k8s-token";

            extraFlags = toString [
              "--cluster-cidr=10.42.0.0/16"
              "--cluster-init"
              "--disable-network-policy"
              "--disable=servicelb"
              # Disable the bundled traefik addon: it's unused (no ingresses
              # or issuers reference it) and its traefik-crd job crash-loops
              # trying to adopt the raw-installed Gateway API CRDs. Ingress is
              # Cilium; Gateway API CRDs are provided by the Flux traefik HR.
              "--disable=traefik"
              "--flannel-backend=none"
              "--service-cidr=10.43.0.0/16"
              "--tls-san=home-k8s-master-1.tail476348.ts.net"
              "--tls-san=100.87.232.102"
              "--write-kubeconfig-mode \"0400\""
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

        # Cilium L7LB (Gateway API / Ingress) requires accept_local=1 +
        # route_localnet=1 on the external interface so the kernel
        # delivers TPROXY-redirected packets (originated from non-local
        # src) to envoy's 127.0.0.1 listening sockets. Without these,
        # external SYNs hit the iptables CILIUM_PRE_mangle TPROXY rule
        # (counter rises) but socket lookup silently drops the packet —
        # every Gateway/Ingress VIP TIMEOUTs externally while
        # host-originated curl works because OUTPUT bypasses PREROUTING.
        boot.kernel.sysctl = {
          "net.ipv4.conf.enp1s0.accept_local" = 1;
          "net.ipv4.conf.enp1s0.route_localnet" = 1;
          "net.ipv4.conf.all.accept_local" = 1;
        };

        # Hosts the home-nix-builder-amd64 GHA runner scale-set; pods
        # hostPath-mount /nix/store + /nix/var and build via the host
        # daemon, so every desktop closure lands here. Outputs are pushed
        # to api.nixcache.org by the workflow before the pod exits, so
        # local copies are disposable — keep retention short and let the
        # daemon prune mid-build under disk pressure.
        nix = {
          gc = {
            dates = lib.mkForce "daily";
            options = lib.mkForce "--delete-older-than 3d";
          };

          settings = {
            min-free = 50 * 1024 * 1024 * 1024;
            max-free = 100 * 1024 * 1024 * 1024;
            auto-optimise-store = lib.mkForce true;

            # This node also runs the k3s control plane (apiserver + etcd).
            # Default max-jobs=auto (16) x cores=0 (all) lets the GHA nix
            # builder oversubscribe every core, driving loadavg ~10 and
            # starving etcd/apiserver. Cap to <=2 concurrent builds x 4 cores
            # = 8 cores max, leaving the other 8 for the control plane.
            max-jobs = 2;
            cores = 4;
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
            ] ++ outputs.lib.sshKeys.remoteBuilders;
          };
      })
    ];
  };
}
