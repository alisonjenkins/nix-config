{ inputs, self, ... }:
let
  system = "x86_64-linux";
  lib = inputs.nixpkgs.lib;
  inherit (self) outputs;
  bluetoothMacs = {
    sonyHeadset = "88:C9:E8:06:5E:9C";
  };
in {
  flake.nixosConfigurations.ali-work-laptop = lib.nixosSystem rec {
    specialArgs = {
      username = "ali";
      inherit inputs outputs;
    };
    modules = [
      { nixpkgs.hostPlatform = system; }

      # Custom modules via flake outputs
      self.nixosModules.desktop-1password
      self.nixosModules.desktop-aws-tools
      self.nixosModules.desktop-base
      self.nixosModules.desktop-greetd-regreet
      self.nixosModules.desktop-kde-connect
      self.nixosModules.desktop-kubernetes
      self.nixosModules.desktop-kwallet
      self.nixosModules.desktop-local-k8s
      self.nixosModules.desktop-media
      self.nixosModules.hardware-fingerprint
      self.nixosModules.hardware-touchpad
      self.nixosModules.audio-context-suspend
      self.nixosModules.base
      self.nixosModules.desktop
      self.nixosModules.development-web
      self.nixosModules.libvirtd
      self.nixosModules.nohang
      self.nixosModules.uresourced
      self.nixosModules.virtual-cameras
      self.nixosModules.locale
      self.nixosModules.niks3-cache-push
      self.nixosModules.llama-swap
      self.nixosModules.mosh
      self.nixosModules.sunshine
      self.nixosModules.podman
      self.nixosModules.wifi-regdom-from-timezone
      self.nixosModules.ali-work-laptop-hardware
      self.nixosModules.ali-work-laptop-disko-config

      # External flake modules
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      inputs.nix-flatpak.nixosModules.nix-flatpak
      inputs.nur.modules.nixos.default
      inputs.sops-nix.nixosModules.sops

      # Home-manager configuration
      ({ lib, pkgs, ... }: {
        # Must be a single executable: home-manager word-splits
        # $HOME_MANAGER_BACKUP_COMMAND and appends the target as $1.
        home-manager.backupCommand = lib.getExe pkgs.hm-backup-file;
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.${specialArgs.username} = {
          imports = [ self.homeModules.home-linux self.homeModules.local-llm-client ];

          # The delegation skill's scripts bypass their own profile queue and
          # talk to llama-swap (modules.llama-swap), which queues and swaps
          # models itself. model is the default; small, fast, dense and coder
          # can be requested per call.
          modules.localLlmClient = {
            enable = true;
            url = "http://127.0.0.1:8080";
            model = "fast";
            context = 65536;
          };

          # Sync mic mute LED with PipeWire state by also toggling the ALSA
          # Capture Switch, which drives the audio-micmute LED trigger.
          custom.niri.micMuteShellCommand = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle; if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED; then amixer -q -c 0 sset Capture nocap; else amixer -q -c 0 sset Capture cap; fi";
        };
        home-manager.extraSpecialArgs =
          specialArgs
          // {
            hostname = "ali-work-laptop";
            bluetoothHeadsetMac = bluetoothMacs.sonyHeadset;
            gitEmail = "1176328+alisonjenkins@users.noreply.github.com";
            gitGPGSigningKey = outputs.lib.sshKeys.primary;
            gitUserName = "Alison Jenkins";
            github_clone_ssh_host_personal = "pgithub.com";
            github_clone_ssh_host_work = "github.com";
            # This host is dormant, so it carries no work identity: the work
            # SSH keys now come from sops and only on machines that opt in.
            # To make it a work machine again, set workIdentity = true and
            # workIdentitySecretsFile = self + "/secrets/ali-work-laptop/work-identity.enc.yaml"
            # (its &server_ali-work-laptop age recipient already exists), then
            # switch primarySSHKey/azureDevopsRsaKey to ~/.ssh/id_work{,_rsa}.pub.
            primarySSHKey = "~/.ssh/id_personal.pub";
          };
      })

      # Host-specific configuration
      ({ config, lib, inputs, outputs, pkgs, ... }: {
        modules.desktop-1password.enable = true;
        modules.desktop-aws-tools.enable = true;
        modules.desktop-base.enable = true;
        modules.desktop-greetd-regreet = {
          enable = true;
          video.enable = true;
        };
        modules.desktop-kde-connect.enable = true;
        modules.desktop-kubernetes.enable = true;
        modules.desktop-kwallet.enable = true;
        modules.desktop-local-k8s.enable = true;
        modules.desktop-media.enable = true;
        modules.virtual-cameras.enable = true;
        modules.hardware-fingerprint = {
          enable = true;
          username = "ali";
        };
        modules.hardware-touchpad.enable = true;
        modules.nohang = {
          enable = true;
          enableDesktopNotifications = true;
        };
        modules.uresourced.enable = true;
        # TODO: Enable once secrets/niks3-token.enc.yaml is created with sops
        # modules.niks3CachePush = {
        #   enable = true;
        #   authTokenFile = config.sops.secrets.niks3-token.path;
        # };
        #
        # sops.secrets.niks3-token = {
        #   sopsFile = self + "/secrets/niks3-token.enc.yaml";
        #   key = "niks3_token";
        # };

        modules.base = {
          enable = true;
          enableImpermanence = true;
          enableCachyOSKernel = true;
          bootLoader = "secure-boot";
          pcr15Value = "2ed3e75741c65cda190d143376c463c88557e8d7ab53f8dfe788a263aaec50b7";
          suspendState = "mem";
          hibernateMode = "shutdown";
          timezone = null;  # Use automatic-timezoned for VPN-proof timezone detection
        };

        services.automatic-timezoned.enable = true;
        modules.wifiRegdomFromTimezone.enable = true;
        modules.locale.enable = true;
        modules.mosh.enable = true;
        modules.sunshine.enable = true;
        # One OpenAI endpoint on :8080 that queues requests and loads models on
        # demand (llama-swap spawns a llama-server per model). Unified memory:
        # ~118 GiB of GTT is usable, so the three small models stay co-resident
        # and only the big coder model evicts them (the resident group). Replaces
        # the always-on 27B (modules.llama-cpp) and the delegation skill's own
        # profile manager on this host; delegation talks to it through
        # modules.localLlmClient (home config above). The 122B-A10B (~86 GiB) is
        # left out: /nix has ~145 GiB free and the set below already fetches
        # ~93 GiB.
        modules.llama-swap = let
          q8Cache = [ "--flash-attn" "on" "--cache-type-k" "q8_0" "--cache-type-v" "q8_0" ];
          coding = [ "--temp" "0.6" "--top-p" "0.95" "--top-k" "20" "--min-p" "0" ];
        in {
          enable = true;
          # Models outside a group share one swap-exclusive slot: loading
          # coder unloads the resident group, and the reverse.
          groups.resident = { };
          models = {
            # Qwen3.5-9B Q6_K, MTP speculative decoding (127 tok/s on
            # ali-desktop): small edits and lookups.
            small = {
              modelFile = pkgs.llama-models.qwen3-5-9b-mtp-q6-k.modelFile;
              contextSize = 32768;
              extraArgs = [ "--spec-type" "draft-mtp" "--spec-draft-n-max" "2" ] ++ coding ++ q8Cache;
              group = "resident";
            };
            # Qwen3.6-35B-A3B UD-Q4_K_XL (~21 GiB), the Q4 of ali-desktop's
            # IQ3_S `fast`: new files, edits and review fixes from a spec.
            fast = {
              modelFile = pkgs.llama-models.qwen3-6-35b-a3b-ud-q4-k-xl.modelFile;
              contextSize = 65536;
              extraArgs = coding ++ q8Cache;
              group = "resident";
            };
            # Qwen3.6-27B dense UD-Q5_K_XL (~18.7 GiB), the previous
            # always-on model; the alias keeps opencode's "qwen3-32b" id working.
            dense = {
              modelFile = pkgs.llama-models.qwen3-6-27b-ud-q5-k-xl.modelFile;
              contextSize = 131072;
              extraArgs = [
                "--flash-attn" "on" "--cache-type-k" "q4_0" "--cache-type-v" "q4_0"
                "--reasoning-format" "deepseek" "--reasoning" "off"
              ];
              aliases = [ "qwen3-32b" ];
              group = "resident";
            };
            # Qwen3-Coder-Next 80B-A3B UD-Q4_K_XL (~46 GiB): the heavy coder.
            coder = {
              modelFile = pkgs.llama-models.qwen3-coder-next-ud-q4-k-xl.modelFile;
              contextSize = 65536;
              extraArgs = coding ++ q8Cache;
            };
          };
        };
        modules.libvirtd.enable = true;
        modules.podman.enable = true;
        modules.podman.enableQemuBinfmt = true;

        modules.desktop = {
          enable = true;
          antigravityCli.enable = false;

          power = {
            hibernateDelaySec = "1h";  # Hibernate after 1 hour of suspend
            handleLidSwitch = "suspend-then-hibernate";
            handleLidSwitchExternalPower = "suspend-then-hibernate";
            handleLidSwitchDocked = "ignore";
            cleanWifiOnSuspend = true;
          };

          pipewire.quantum = 512;
        };

        services.audio-context-suspend = {
          enable = true;
          user = "ali";
          syncMicMuteLed = true;
        };

        # Override disko's keyFile (only used during initial install) so it doesn't
        # interfere with TPM2 auto-unlock in the initrd crypttab
        boot.initrd.luks.devices.crypted.keyFile = lib.mkForce null;

        # Bypass kernel workqueues for dm-crypt — significant NVMe
        # I/O improvement on a CPU with hardware AES (the actual
        # crypto is near-free; the workqueue latency was
        # dominating). Runtime-only, applies on next boot.
        boot.initrd.luks.devices.crypted.crypttabExtraOpts = [
          "no-read-workqueue"
          "no-write-workqueue"
        ];

        boot = {
          kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-zen4;

          # Blacklist amd_pmf to prevent TEE errors after hibernate resume
          # The driver causes system instability with constant "TEE enact cmd failed" errors
          blacklistedKernelModules = [ "amd_pmf" ];

          extraModprobeConfig = ''
            options snd-hda-intel index=1,0
          '';

          kernelParams = [
            "amd_iommu=off"
            "amdgpu.runpm=0"  # Disable GPU runtime power management to prevent SMU race after suspend

            # Strix Halo unified memory: expose ~115GB to GPU via GTT/TTM
            # instead of relying on BIOS UMA carve-out (keep BIOS at Auto/512MB)
            "amdgpu.gttsize=117760"
            "ttm.page_pool_size=25600000"
            "ttm.pages_limit=25600000"
          ];

        };

        console.keyMap = "us";

        environment = {
          pathsToLink = [ "/share/zsh" ];

          variables = {
            # NIXOS_OZONE_WL = "1";
            # Datadog org lives on the US3 site; pup defaults to US1
            # (datadoghq.com), which breaks OAuth token exchange
            # (invalid_grant). Pin the site for pup + other DD tooling.
            DD_SITE = "us3.datadoghq.com";
            PATH = [
              "\${HOME}/.local/bin"
              "\${HOME}/.config/rofi/scripts"
            ];
            ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
          };

          systemPackages = with pkgs; [
            powershell
            pup
            sbctl
            slack
            # wallpapers # TODO: re-enable after wallpapers relocated from LFS
          ];
        };

        hardware = {
          graphics.enable = true;
        };

        networking = {
          hostName = "ali-work-laptop";
          networkmanager = {
            enable = true;
            # mt76 does power-save transitions in software; reports of latency
            # spikes and deauth loops on mt7921/mt7925. Unproven on this card.
            wifi.powersave = false;
          };
        };

        nixpkgs = {
          overlays = [
            inputs.nur.overlays.default
            inputs.fenix.overlays.default
            outputs.overlays._1password
            outputs.overlays.additions
            outputs.overlays.master-packages
            outputs.overlays.modifications
            outputs.overlays.stable-packages
            outputs.overlays.tmux-sessionizer
            outputs.overlays.unstable-packages
            outputs.overlays.linux-firmware
          ];
          config = {
            allowUnfree = true;
          };
        };

        programs = {
          niri = {
            enable = true;
            package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri;
          };
        };

        security.rtkit.enable = true;

        # Reduce ZRAM for faster hibernation (less data to serialize)
        zramSwap.memoryPercent = lib.mkForce 50;

        services = {
          pulseaudio = {
            enable = false;
          };

          pipewire = {
            enable = true;
            alsa.enable = true;
            alsa.support32Bit = true;
            pulse.enable = true;
          };

          power-profiles-daemon = {
            enable = lib.mkForce true;
          };

          tlp = {
            enable = lib.mkForce false;
          };

          thermald = {
            enable = true;
          };

          xserver = {
            videoDrivers = [ "amdgpu" ];
            xkb = {
              layout = "us";
              variant = "";
            };
          };
        };

        system = {
          stateVersion = "24.05";
        };

        users = {
          users = {
            ali = {
              isNormalUser = true;
              description = "Alison Jenkins";
              # initialPassword = "initPw!";
              hashedPasswordFile = "/persistence/passwords/ali";
              extraGroups = [ "networkmanager" "wheel" "docker" "realtime" "input" ];

              openssh.authorizedKeys.keys = outputs.lib.sshKeys.all;
            };
          };
        };

        xdg.portal = {
          enable = true;
          xdgOpenUsePortal = true;
        };
      })
    ];
  };
}
