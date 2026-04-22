# Base system configuration module
{ config, lib, pkgs, inputs, outputs, ... }:
let
  cfg = config.modules.base;
in
{
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.lanzaboote.nixosModules.lanzaboote
    ../luksPCR15
    ./vm-variant.nix
  ] ++ lib.optional (builtins.pathExists /etc/nixos/cachix/ajenkins-public.nix) [ /etc/nixos/cachix/ajenkins-public.nix ];

  options.modules.base = {
    enable = lib.mkEnableOption "base system configuration";

    consoleKeyMap = lib.mkOption {
      type = lib.types.str;
      default = "us";
      description = "Console keymap";
    };

    enableICMPPing = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow incoming ICMP echo requests (ping). Disabled by default for security.";
    };

    enableIPv6 = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable IPv6";
    };

    enableImpermanence = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable tmpfs root with persistence";
    };

    enableOpenSSH = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable OpenSSH";
    };

    enableTailscale = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Tailscale VPN";
    };

    impermanencePersistencePath = lib.mkOption {
      type = lib.types.str;
      default = "/persistence";
      description = "Path for impermanence persistence";
    };

    beesdFilesystems = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Bees deduplication filesystems";
    };

    timezone = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "Europe/London";
      description = "System timezone. Set to null for automatic timezone detection.";
    };

    useAliNeovim = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use ali-neovim flake package";
    };

    bootLoader = lib.mkOption {
      type = lib.types.enum [ "systemd-boot" "grub" "secure-boot" ];
      default = "systemd-boot";
      description = "Boot loader to use. 'secure-boot' uses Lanzaboote with TPM support.";
    };

    enableCachyOSKernel = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable CachyOS kernel overlay. Only needed on hosts using CachyOS kernel packages.";
    };

    pcr15Value = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "TPM PCR15 value for LUKS unlocking (only used with secure-boot)";
    };

    suspendState = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "mem" "standby" "freeze" ]);
      default = "mem";
      description = ''
        Suspend state to use. Set to null to auto-detect.
        'mem' is S3 deep sleep, 'standby' is S1, 'freeze' is s2idle.
        Some hardware only supports s2idle (freeze), in which case set to null or "freeze".
      '';
    };

    hibernateMode = lib.mkOption {
      type = lib.types.enum [ "platform" "shutdown" ];
      default = "platform";
      description = ''
        Hibernate mode. 'platform' calls ACPI S4 firmware hooks (safer, slower).
        'shutdown' powers off immediately after writing the image (faster, skips firmware hooks).
      '';
    };

    enableMGLRU = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable MGLRU (Multigenerational LRU) tuning via min_ttl_ms.
        Improves page reclamation efficiency under memory pressure,
        reducing swap thrashing. Requires kernel 6.1+ with MGLRU support.
      '';
    };

    enableInitrdDebug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Diagnostic-only. Turns the initrd into a debugging surface:
          - forces sulogin to accept passwordless login (SYSTEMD_SULOGIN_FORCE=1)
          - auto-dumps `journalctl -xb` to the console on emergency.target

        SECURITY: when enabled, anyone with physical access can drop into a
        root shell in the initrd (before LUKS unlock) and tamper with the
        unencrypted EFI partition or re-sign boot images. Only enable on the
        specific host being diagnosed, and disable again immediately after.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = (cfg.bootLoader == "secure-boot") -> (cfg.pcr15Value != null);
          message = "modules.base.pcr15Value must be set when using secure-boot boot loader";
        }
      ];

    }

    # Core base configuration
    {
      console.keyMap = cfg.consoleKeyMap;

      time.timeZone = lib.mkIf (cfg.timezone != null) cfg.timezone;

      boot = {
        consoleLogLevel = 0;
        kernelModules = lib.optionals cfg.enableCachyOSKernel [
          "sch_dualpi2"
        ];

        initrd = {
          verbose = false;

          availableKernelModules = [ "lz4" "lz4_compress" ];

          # CachyOS Linux 7 builds cipher primitives (aes, xts, sha256, cbc, lrw,
          # sha1/512, blowfish, twofish, serpent) into the kernel (=y), so naming
          # them in cryptoModules breaks makeModulesClosure. These three stay =m
          # and cryptsetup needs them at runtime — without them the initrd's
          # systemd-cryptsetup@.service dies before it can prompt for a passphrase.
          luks.cryptoModules = lib.mkIf cfg.enableCachyOSKernel (lib.mkForce [
            "cryptd"
            "af_alg"
            "algif_skcipher"
          ]);

          systemd = {
            enable = true;
            # Allow logging into the initrd emergency shell without a root password.
            # Needed to diagnose early-boot failures (e.g. systemd-cryptsetup) when
            # the machine can't pivot to the real root, so /persistence/passwords/root
            # is unreachable and sulogin locks us out.
            emergencyAccess = true;
          };
        };

        kernelParams = [
          "amdgpu.ppfeaturemask=0xfff7ffff"
          "hibernate=lz4"
          "preempt=full"
        ] ++ lib.optionals cfg.enableCachyOSKernel [
          # CachyOS LTO builds fail the cryptomgr self-test for xts(aes)/AES-NI
          # at late_initcall time, which marks the template broken. dm-crypt
          # then gets -ENOENT back from crypto_alloc_skcipher("xts(aes)") and
          # the reload ioctl surfaces that as EINVAL — blocking LUKS unlock in
          # the initrd. Skipping the self-tests lets the template stay usable.
          "cryptomgr.notests=1"
        ];

        kernel = {
          sysctl = {
            "dev.hpet.max-user-freq" = 1000;
            "fs.dentry-negative" = 1;

            # Network Perf Tuning
            "net.core.default_qdisc" = lib.mkDefault "dualpi2";
            "net.core.netdev_budget" = 600;
            "net.core.netdev_budget_usecs" = 8000;
            "net.core.netdev_max_backlog" = 16384;
            "net.core.optmem_max" = 65536;
            "net.core.rmem_default" = 1048576;
            "net.core.rmem_max" = 16777216;
            "net.core.somaxconn" = 8192;
            "net.core.wmem_default" = 1048576;
            "net.core.wmem_max" = 16777216;
            "net.ipv4.conf.all.accept_redirects" = 0;
            "net.ipv4.conf.all.log_martians" = 0;
            "net.ipv4.conf.all.rp_filter" = 1;
            "net.ipv4.conf.all.secure_redirects" = 0;
            "net.ipv4.conf.all.send_redirects" = 0;
            "net.ipv4.conf.default.accept_redirects" = 0;
            "net.ipv4.conf.default.log_martians" = 0;
            "net.ipv4.conf.default.rp_filter" = 1;
            "net.ipv4.conf.default.secure_redirects" = 0;
            "net.ipv4.conf.default.send_redirects" = 0;
            "net.ipv4.icmp_echo_ignore_all" = if cfg.enableICMPPing then 0 else 1;
            "net.ipv4.tcp_congestion_control" = "bbr";
            "net.ipv4.tcp_ecn" = 1;
            "net.ipv4.tcp_fastopen" = 3;
            "net.ipv4.tcp_fin_timeout" = 10;
            "net.ipv4.tcp_keepalive_intvl" = 10;
            "net.ipv4.tcp_keepalive_probes" = 6;
            "net.ipv4.tcp_keepalive_time" = 60;
            "net.ipv4.tcp_max_syn_backlog" = 8192;
            "net.ipv4.tcp_max_tw_buckets" = 2000000;
            "net.ipv4.tcp_mtu_probing" = 1;
            "net.ipv4.tcp_rfc1337" = 1;
            "net.ipv4.tcp_rmem" = "4096 1048576 16777216";
            "net.ipv4.tcp_sack" = 1;
            "net.ipv4.tcp_slow_start_after_idle" = 0;
            "net.ipv4.tcp_syncookies" = 1;
            "net.ipv4.tcp_timestamps" = 1;
            "net.ipv4.tcp_tw_reuse" = 1;
            "net.ipv4.tcp_wmem" = "4096 1048576 16777216";
            "net.ipv4.udp_rmem_min" = 8192;
            "net.ipv4.udp_wmem_min" = 8192;
            "net.ipv6.conf.all.accept_redirects" = 0;
            "net.ipv6.conf.default.accept_redirects" = 0;
            "net.ipv4.tcp_window_scaling" = 1;

            # Virtual memory tuning
            "vm.swappiness" = lib.mkDefault 10;
            "vm.dirty_ratio" = 20;
            "vm.dirty_background_ratio" = 5;
            "vm.vfs_cache_pressure" = 25;
          };
        };

        loader = {
          timeout = lib.mkDefault 5;
          efi = {
            canTouchEfiVariables = true;
            efiSysMountPoint = "/boot";
          };
        };
      };

      environment = {
        systemPackages = with pkgs; [
          btop
          cachix
          dig
          git
          htop
          iotop
          just
          lshw
          nethogs
          pciutils
          rush-parallel
          tmux
          trash-cli
          vim
          yazi
        ] ++ (if (cfg.bootLoader == "secure-boot") then [pkgs.sbctl] else [])
        ++ (if cfg.useAliNeovim then [
          inputs.ali-neovim.packages.${pkgs.stdenv.hostPlatform.system}.nvim
        ] else [pkgs.neovim]);
      };

      networking = {
        enableIPv6 = cfg.enableIPv6;

        networkmanager = {
          enable = lib.mkDefault true;
        };
      };

      nixpkgs = {
        config = {
          allowUnfree = true;
        };

        overlays = [
          inputs.nur.overlays.default
          inputs.fenix.overlays.default
          outputs.overlays.additions
          outputs.overlays.master-packages
          outputs.overlays.modifications
          outputs.overlays.stable-packages
          outputs.overlays.tmux-sessionizer
          outputs.overlays.systemd
          outputs.overlays.unstable-packages
        ] ++ lib.optional cfg.enableCachyOSKernel inputs.nix-cachyos-kernel.overlays.pinned;
      };

      nix = {
        package = lib.mkDefault pkgs.nixVersions.stable;

        gc = {
          automatic = lib.mkDefault true;
          dates = lib.mkDefault "weekly";
          options = lib.mkDefault "--delete-older-than 60d";
        };

        settings = {
          auto-optimise-store = lib.mkDefault false;
          cores = lib.mkDefault 0;
          experimental-features = lib.mkDefault [ "nix-command" "flakes" "ca-derivations" ];
          download-buffer-size = lib.mkDefault 268435456; # 256 MiB
          eval-cache = lib.mkDefault true;
          max-jobs = lib.mkDefault "auto";
          trusted-users = [ "root" "@wheel" ];

          substituters = lib.mkBefore [
            "https://cache.nixcache.org"
            "https://attic.xuyh0120.win/lantian"
            "https://cache.garnix.io"
            "https://cache.nixos.org"
            "https://jovian.cachix.org"
            "https://nix-community.cachix.org"
            "https://nix-gaming.cachix.org"
            "https://nixpkgs-wayland.cachix.org"
            "https://fenix.cachix.org"
          ];

          trusted-public-keys = [
            "nixcache.org-1:fd7sIL2BDxZa68s/IqZ8kvDsxsjt3SV4mQKdROuPoak="
            "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            "jovian.cachix.org-1:mAWLjAxLNI3RiPXtAE24VSpamW0gUfnGzroKvA/x2yE="
            "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
            "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
            "fenix.cachix.org-1:ecJhr+RdYEdcVgUkjruiYhjbBloIEGov7bos90cZi0Q="
          ];
        };
      };

      programs = {
        zsh = {
          enable = true;
        };
      };

      security = {
        rtkit.enable = true;

        pam = {
          loginLimits = [
            {
              domain = "@realtime";
              type = "-";
              item = "rtprio";
              value = 98;
            }
            {
              domain = "@realtime";
              type = "-";
              item = "memlock";
              value = "unlimited";
            }
            {
              domain = "@realtime";
              type = "-";
              item = "nice";
              value = -11;
            }
          ];
        };

        sudo = {
          enable = true;
          wheelNeedsPassword = true;
        };
      };

      systemd.services.NetworkManager-wait-online.enable = false;

      services = {
        fstrim.enable = true;
        irqbalance.enable = true;
        pulseaudio.enable = false;
        resolved.enable = true;

        beesd = {
          filesystems = cfg.beesdFilesystems;
        };

        fwupd = {
          enable = lib.mkDefault true;
        };

        openssh = {
          enable = cfg.enableOpenSSH;

          hostKeys = let
            keyDir = if cfg.enableImpermanence
              then "${cfg.impermanencePersistencePath}/etc/ssh/keys"
              else "/etc/ssh";
          in [
            {
              bits = 4096;
              path = "${keyDir}/ssh_host_rsa_key";
              type = "rsa";
            }
            {
              path = "${keyDir}/ssh_host_ed25519_key";
              type = "ed25519";
            }
          ];

          settings = {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            PermitRootLogin = "no";
          };
        };

        tailscale = {
          enable = cfg.enableTailscale;
          package = lib.mkDefault pkgs.unstable.tailscale;
        };

        timesyncd = {
          enable = lib.mkDefault true;
        };

        udev = {
          extraRules = ''
            KERNEL=="cpu_dma_latency", GROUP="realtime"
          '';
        };
      };

      users = {
        users = {
          colord = {
            isSystemUser = true;
            group = "colord";
          };
        };
        groups = {
          colord = {};
          realtime = {};
        };
      };

      zramSwap = {
        enable = true;
        algorithm = "zstd";
        memoryPercent = 100;
      };

      # Reduce hibernate image size target to 8GB (default is ~2/5 of RAM)
      # Smaller image = less data to write/read = faster hibernate and resume
      systemd.tmpfiles.rules = [
        "w /sys/power/image_size - - - - 8589934592"
      ]
      # MGLRU tuning: set min_ttl_ms to improve page reclamation under memory pressure
      ++ lib.optionals cfg.enableMGLRU [
        "w /sys/kernel/mm/lru_gen/min_ttl_ms - - - - 1000"
      ];

      # Optimal suspend and hibernate settings
      systemd.sleep = {
        extraConfig = ''
          # Hibernate mode - configurable per-host
          HibernateMode=${cfg.hibernateMode}

          # Suspend settings - configurable per-host
          # 'mem' is S3 deep sleep, 'freeze' is s2idle (for hardware that doesn't support S3)
          # Set to null to let the system auto-detect
          ${lib.optionalString (cfg.suspendState != null) "SuspendState=${cfg.suspendState}"}

          AllowHibernation=yes
          AllowSuspend=yes
          AllowHybridSleep=yes
          AllowSuspendThenHibernate=yes
        '';
      };
    }

    # GRUB bootloader
    (lib.mkIf (cfg.bootLoader == "grub") {
      boot.loader.grub = {
        devices = [ "nodev" ];
        efiInstallAsRemovable = false;
        efiSupport = true;
        enable = true;
        useOSProber = true;

        theme = lib.mkDefault (pkgs.stdenv.mkDerivation {
          pname = "distro-grub-themes";
          version = "3.1";
          src = pkgs.fetchFromGitHub {
            owner = "AdisonCavani";
            repo = "distro-grub-themes";
            rev = "v3.1";
            hash = "sha256-ZcoGbbOMDDwjLhsvs77C7G7vINQnprdfI37a9ccrmPs=";
          };
          installPhase = "cp -r customize/nixos $out";
        });
      };
    })

    # systemd-boot bootloader
    (lib.mkIf (cfg.bootLoader == "systemd-boot") {
      boot.loader.systemd-boot = {
        consoleMode = "max";
        enable = true;
        memtest86.enable = true;
        netbootxyz.enable = true;
      };
    })

    # Secure boot (Lanzaboote) - inherits systemd-boot config but replaces it with Lanzaboote
    (lib.mkIf (cfg.bootLoader == "secure-boot") {
      boot = {
        loader.systemd-boot = {
          consoleMode = "max";
          enable = lib.mkForce false;
          memtest86.enable = true;
          netbootxyz.enable = true;
        };

        # Systemd initrd is required for PCR15 verification (luksPCR15 module)
        initrd.systemd.enable = true;

        lanzaboote = {
          enable = true;
          pkiBundle = "/var/lib/sbctl";
        };
      };

      systemIdentity = {
        enable = true;
        pcr15 = cfg.pcr15Value;
      };
    })

    # Initrd debug scaffolding — gated to a single host at a time.
    # See modules.base.enableInitrdDebug description for the security note.
    (lib.mkIf (cfg.bootLoader == "secure-boot" && cfg.enableInitrdDebug) {
      # Baked into the UKI (and therefore into the secure-boot signature).
      # sulogin reads this from /proc/cmdline when the env var isn't set.
      boot.kernelParams = [ "SYSTEMD_SULOGIN_FORCE=1" ];

      # vfat so the operator can mount the ESP from the emergency shell and
      # write diagnostic dumps to somewhere that survives reboot.
      boot.initrd.supportedFilesystems = [ "vfat" ];

      boot.initrd.systemd.services = {
        # emergencyAccess writes an empty root password into the initrd's
        # /etc/shadow, but sulogin still locks us out on early-boot failures
        # without --force. Env-var route triggers --force unconditionally.
        emergency.serviceConfig.Environment = "SYSTEMD_SULOGIN_FORCE=1";
        rescue.serviceConfig.Environment    = "SYSTEMD_SULOGIN_FORCE=1";

        # If sulogin still loses, dump journalctl -xb to the console so the
        # operator can at least read and photograph the failure reason.
        emergency-journal-dump = {
          description = "Dump journal to console on emergency";
          wantedBy = [ "emergency.target" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.systemd}/bin/journalctl -xb --no-pager";
            StandardOutput = "journal+console";
            StandardError  = "journal+console";
          };
        };
      };
    })

    # Impermanence
    (lib.mkIf cfg.enableImpermanence {
      environment = {
        persistence = {
          "${cfg.impermanencePersistencePath}" = {
            hideMounts = true;
            directories = [
              "/etc/NetworkManager/system-connections"
              "/etc/luks"
              "/var/lib/nixos"
              "/var/lib/systemd/coredump"
              "/var/log"
              {
                directory = "/var/lib/private";
                user = "root";
                group = "root";
                mode = "0700";
              }
              {
                directory = "/var/lib/samba";
                user = "root";
                group = "root";
                mode = "0700";
              }
              {
                directory = "/etc/wireguard";
                user = "root";
                group = "root";
                mode = "u=rwx,g=rx,o=";
              }
              {
                directory = "/etc/nixos/cachix";
                user = "root";
                group = "root";
                mode = "u=rwx,g=,o=";
              }
              {
                directory = "/var/lib/iwd";
                user = "root";
                group = "root";
                mode = "u=rwx,g=,o=";
              }
            ] ++ (if cfg.enableTailscale then [
              {
                directory = "/var/lib/tailscale";
                user = "root";
                group = "root";
                mode = "0700";
              }
            ] else [])
            ++ (if (cfg.bootLoader == "secure-boot") then [
              {
                directory = "/var/lib/sbctl";
                group = "root";
                mode = "u=rwx,g=,o=";
                user = "root";
              }
            ] else []
            );
            files = [
              "/etc/machine-id"
              {
                file = "/var/keys/secret_file";
                parentDirectory = { mode = "u=rwx,g=,o="; };
              }
            ];
          };
        };
      };
    })
  ]);
}
