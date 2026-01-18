{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.modules.desktop;
in
{
  imports = [
    inputs.lsfg-vk-flake.nixosModules.default
    inputs.stylix.nixosModules.stylix
  ];

  options.modules.desktop = {
    enable = mkEnableOption "desktop environment configuration";

    power = {
      hibernateDelaySec = mkOption {
        type = types.str;
        default = "2h";
        description = ''
          Time to wait after suspend before hibernating when using suspend-then-hibernate.
          This establishes a balance between speed (stay in suspend for quick resume)
          and safety (hibernate to prevent data loss if battery dies).

          Examples: "30m" (30 minutes), "2h" (2 hours), "4h" (4 hours)
          Default: "2h" - good balance for most laptops
        '';
      };

      suspendEstimationSec = mkOption {
        type = types.int;
        default = 3600;
        description = ''
          Fallback time in seconds for estimating when to hibernate if battery detection fails.
          Only used when suspend-then-hibernate is active and battery monitoring is unavailable.
          Default: 3600 (1 hour)
        '';
      };

      handleLidSwitch = mkOption {
        type = types.enum [ "ignore" "poweroff" "reboot" "halt" "suspend" "hibernate" "hybrid-sleep" "suspend-then-hibernate" "lock" ];
        default = "suspend-then-hibernate";
        description = ''
          Action to take when laptop lid is closed.
          - suspend: Fast, uses RAM (battery drain if left too long)
          - hibernate: Slow to enter/exit, saves to disk (no battery drain, safe)
          - suspend-then-hibernate: Suspends first, then hibernates after HibernateDelaySec
          - lock: Just lock the screen
          Default: "suspend-then-hibernate" for best balance
        '';
      };

      handleLidSwitchExternalPower = mkOption {
        type = types.enum [ "ignore" "poweroff" "reboot" "halt" "suspend" "hibernate" "hybrid-sleep" "suspend-then-hibernate" "lock" ];
        default = "lock";
        description = ''
          Action to take when laptop lid is closed while on external power.
          Default: "lock" - don't suspend when plugged in (useful for docked setups)
        '';
      };

      handleLidSwitchDocked = mkOption {
        type = types.enum [ "ignore" "poweroff" "reboot" "halt" "suspend" "hibernate" "hybrid-sleep" "suspend-then-hibernate" "lock" ];
        default = "ignore";
        description = ''
          Action to take when laptop lid is closed while docked (external display connected).
          Default: "ignore" - allow using laptop closed with external display
        '';
      };
    };

    pipewire = {
      quantum = mkOption {
        type = types.int;
        default = 256;
        description = "PipeWire default quantum size for audio latency configuration";
      };

      minQuantum = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "PipeWire minimum quantum size. If null, uses quantum value for fixed quantum.";
      };

      maxQuantum = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "PipeWire maximum quantum size. If null, uses quantum value for fixed quantum.";
      };

      allowedSampleRates = mkOption {
        type = types.listOf types.int;
        default = [44100 48000];
        description = ''
          List of allowed sample rates for PipeWire audio devices.
          Common rates: 44100 (CD quality), 48000 (professional), 88200, 96000 (high-res).

          Note: Higher sample rates (88200, 96000) require larger quantum values for stability,
          especially with Bluetooth devices. For 96kHz Bluetooth, use quantum >= 1024.

          Default: [44100 48000] for best compatibility and stability.
        '';
      };

      resampleQuality = mkOption {
        type = types.int;
        default = 4;
        description = ''
          PipeWire resample quality (0-15):
          - 0-3: speex-fixed (low quality, fast)
          - 4-7: speex (medium quality, balanced)
          - 8-14: soxr (high quality, slower)
          - 15: soxr-vhq (very high quality, slowest)

          Default is 4 (speex-fixed-3) for balanced quality/performance.
        '';
      };

      suspendTimeoutSeconds = mkOption {
        type = types.int;
        default = 5;
        description = ''
          Seconds of idle time before suspending audio nodes for power saving.
          Set to 0 to disable suspend-on-idle.
          Default is 5 seconds.
        '';
      };

      alsaHeadroom = mkOption {
        type = types.int;
        default = 1024;
        description = ''
          ALSA headroom in samples to prevent audio clipping.
          Larger values provide more protection against clipping but add latency.
          Default is 1024 samples (~21ms at 48kHz).
        '';
      };
    };

    gaming = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable gaming packages and configurations (Steam, GameMode, etc.)";
      };

      gpuVendor = mkOption {
        type = types.enum [ "amd" "nvidia" "intel" "auto" ];
        default = "auto";
        description = ''
          Primary GPU vendor for gaming optimizations.
          Set to "auto" to auto-detect, or specify "amd", "nvidia", or "intel" for vendor-specific optimizations.
        '';
      };

      cpuTopology = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Override Wine CPU topology detection in format "physical:logical".
          Examples: "8:16" for 8 cores/16 threads, "6:12" for 6 cores/12 threads.
          Set to null to let Wine auto-detect.
        '';
      };

      enableDxvkStateCache = mkOption {
        type = types.bool;
        default = true;
        description = "Enable DXVK state cache for faster shader compilation";
      };

      enableVkd3dShaderCache = mkOption {
        type = types.bool;
        default = true;
        description = "Enable VKD3D-Proton shader cache for D3D12 games";
      };

      dxvkHud = mkOption {
        type = types.str;
        default = "0";
        description = ''
          DXVK HUD overlay settings.
          "0" = disabled, "fps" = show FPS, "compiler" = show shader compilation, "full" = all info.
        '';
      };

      enableLargeAddressAware = mkOption {
        type = types.bool;
        default = true;
        description = "Enable large address aware for 32-bit Windows games (allows >2GB RAM usage)";
      };

      shaderCacheBasePath = mkOption {
        type = types.str;
        default = "\${HOME}/.cache";
        description = ''
          Base directory for shader caches (DXVK, VKD3D, etc.).
          Default: "\${HOME}/.cache" (stored in user home directory)

          For better performance on expendable storage, you can set this to a mount
          with aggressive options like barrier=0 and data=writeback, since shader
          caches can be safely rebuilt if corrupted.
        '';
      };

      gpuDevice = mkOption {
        type = types.int;
        default = 0;
        description = ''
          DRM device number for the primary gaming GPU (/sys/class/drm/cardN).
          - 0: Usually integrated GPU or primary GPU
          - 1: Usually discrete GPU on laptops with hybrid graphics
          Check /sys/class/drm/ to identify your GPU device number.
        '';
      };
    };

    lsfg = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Lossless Scaling Frame Generation support";
      };
    };

    cosmic = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable COSMIC desktop environment";
      };
    };

    printing = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable printing support with CUPS and HP printer drivers";
      };
    };

    wifi = {
      optimizeForLowLatency = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Optimize WiFi settings for low latency use cases (gaming, VoIP, real-time communication).
          This disables power save, enables aggressive roaming, and prefers 5GHz/6GHz bands.
        '';
      };

      roamThreshold = mkOption {
        type = types.int;
        default = -70;
        description = ''
          RSSI threshold (in dBm) for roaming on 2.4GHz networks.
          Lower values (e.g., -80) = more aggressive roaming.
          Higher values (e.g., -60) = less aggressive roaming.
          Range: -100 to 1
        '';
      };

      roamThreshold5G = mkOption {
        type = types.int;
        default = -76;
        description = ''
          RSSI threshold (in dBm) for roaming on 5GHz networks.
          Lower values (e.g., -85) = more aggressive roaming.
          Higher values (e.g., -70) = less aggressive roaming.
          Range: -100 to 1
        '';
      };

      bandModifier5GHz = mkOption {
        type = types.float;
        default = 1.0;
        description = ''
          Modifier for 5GHz band preference in network ranking.
          Values > 1.0 prefer 5GHz over 2.4GHz (e.g., 1.5 gives 50% bonus).
          Values < 1.0 penalize 5GHz.
          Set to 0.0 to disable 5GHz entirely.
        '';
      };

      bandModifier6GHz = mkOption {
        type = types.float;
        default = 1.0;
        description = ''
          Modifier for 6GHz band preference in network ranking.
          Values > 1.0 prefer 6GHz (e.g., 1.5 gives 50% bonus).
          Set to 0.0 to disable 6GHz entirely.
        '';
      };
    };

    bluetooth = {
      optimizeForLowLatency = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Optimize Bluetooth settings for low latency use cases (gaming, VoIP, real-time communication).
          This enables fast connectable mode, optimizes connection intervals, and configures
          high-quality audio codecs.
        '';
      };

      enableFastConnectable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable Fast Connectable mode for adapters that support it.
          Allows other devices to connect faster at the cost of increased power consumption.
          Requires kernel 4.1+. Default: true.
        '';
      };

      reconnectAttempts = mkOption {
        type = types.int;
        default = 7;
        description = ''
          Number of attempts to reconnect after a link is lost.
          Set to 0 to disable reconnection feature.
          Default: 7.
        '';
      };

      reconnectIntervals = mkOption {
        type = types.listOf types.int;
        default = [ 1 2 4 8 16 32 64 ];
        description = ''
          Intervals in seconds between reconnection attempts.
          If reconnectAttempts is larger than this list, the last interval is repeated.
          Default: [ 1 2 4 8 16 32 64 ] (exponential backoff).
        '';
      };

      audioCodecPriority = mkOption {
        type = types.listOf types.str;
        default = [ "ldac" "aptx_hd" "aptx" "aac" "sbc_xq" "sbc" ];
        description = ''
          Priority order for Bluetooth audio codecs.
          Higher quality codecs should be listed first.
          Available codecs: ldac, aptx_hd, aptx, aac, sbc_xq, sbc, faststream, lc3.
          Default: [ "ldac" "aptx_hd" "aptx" "aac" "sbc_xq" "sbc" ].
        '';
      };

      ldacQuality = mkOption {
        type = types.enum [ "auto" "hq" "sq" "mq" ];
        default = "auto";
        description = ''
          LDAC codec quality setting:
          - auto: Automatic quality selection based on connection quality
          - hq: High Quality (990 kbps, best quality, highest latency)
          - sq: Standard Quality (660 kbps, balanced)
          - mq: Mobile Quality (330 kbps, lower latency)
          Default: auto.
        '';
      };

      defaultSampleRate = mkOption {
        type = types.int;
        default = 48000;
        description = ''
          Default sample rate for Bluetooth audio in Hz.
          Common values: 44100, 48000, 96000.
          Higher values may improve quality but increase latency.
          Default: 48000.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    # Gaming-specific kernel and system optimizations
    boot.kernel.sysctl = mkMerge [
      (mkIf cfg.gaming.enable {
        # Memory management optimizations for gaming
        "vm.compaction_proactiveness" = 0;          # Disable proactive compaction (reduce background CPU usage)
        "vm.page-cluster" = 0;                      # Disable page clustering for swap (reduce latency)
        "vm.watermark_boost_factor" = 0;            # Disable watermark boosting (reduce memory fragmentation overhead)
        "vm.watermark_scale_factor" = 50;           # Balance between memory availability and disk caching (was 125, default is 10)

        # Scheduler optimizations for gaming
        "kernel.sched_child_runs_first" = 0;        # Parent process runs first (better for game launchers)
        "kernel.sched_autogroup_enabled" = 1;       # Enable automatic process grouping for better desktop responsiveness
        "kernel.sched_cfs_bandwidth_slice_us" = 500; # Reduce CFS bandwidth slice for lower latency
      })
    ];

    # Desktop-specific suspend and hibernate configuration
    systemd.sleep = {
      extraConfig = ''
        # Desktop/laptop specific hibernate timing
        # Delay before hibernating when using suspend-then-hibernate mode
        HibernateDelaySec=${cfg.power.hibernateDelaySec}

        # Fallback estimation if battery monitoring unavailable
        SuspendEstimationSec=${toString cfg.power.suspendEstimationSec}
      '';
    };

    # Create shader cache directories automatically
    systemd.tmpfiles.rules = mkIf cfg.gaming.enable [
      "d ${cfg.gaming.shaderCacheBasePath} 0755 - - -"
      "d ${cfg.gaming.shaderCacheBasePath}/dxvk 0755 - - -"
      "d ${cfg.gaming.shaderCacheBasePath}/vkd3d 0755 - - -"
      "d ${cfg.gaming.shaderCacheBasePath}/nvidia 0755 - - -"
      "d ${cfg.gaming.shaderCacheBasePath}/steam 0755 - - -"
    ];

    services.logind = {
      settings = {
        Login = {
          # Lid switch behavior configuration for laptops
          HandleLidSwitch = cfg.power.handleLidSwitch;
          HandleLidSwitchExternalPower = cfg.power.handleLidSwitchExternalPower;
          HandleLidSwitchDocked = cfg.power.handleLidSwitchDocked;

          # Reduce time before considering idle for better responsiveness
          IdleAction = "ignore";
          IdleActionSec = "30min";

          # Handle power key press (short press = suspend-then-hibernate, long press = poweroff)
          HandlePowerKey = "suspend-then-hibernate";
          HandlePowerKeyLongPress = "poweroff";

          # Handle suspend key
          HandleSuspendKey = "suspend";

          # Handle hibernate key
          HandleHibernateKey = "hibernate";
        };
      };
    };

    environment = {
      systemPackages = with pkgs; [
        # unstable.winboat
        aider-chat-full
        bluetooth-connect
        deepfilternet
        file-roller
        hicolor-icon-theme
        lock-session
        millisecond
        nix-flake-template-init
        oxker
        pciutils
        playerctl
        popsicle
        portaudio
        posting
        powertop
        signal-desktop
        suspendScripts
        television
        unstable.claude-code
        unstable.cobang
        unstable.copilot-cli
        unstable.devenv
        unstable.easyeffects
        unstable.jellycli
        unstable.mission-center
        unstable.nvtopPackages.amd
        unstable.opencode
        unstable.teamtype
        unzip
        wallpapers
        wleave
        zoom-us

        (python3.withPackages (python-pkgs: [
          python-pkgs.boto3
          python-pkgs.pandas
          python-pkgs.requests
          python-pkgs.sounddevice
          python-pkgs.soundfile
        ]))
      ] ++ (optionals cfg.gaming.enable (with pkgs; [
        boilr
        gamemode
        mangohud
        steamtinkerlaunch
        unstable.goverlay
        unstable.heroic-unwrapped
        unstable.protonplus
        unstable.scx.full
        unstable.umu-launcher
      ]))
      ++ (optionals cfg.lsfg.enable [
        pkgs.lsfg-vk-ui
      ])
      ++ (optionals cfg.printing.enable [
        pkgs.hplipWithPlugin
      ]);

      variables = {
        # NIXOS_OZONE_WL = "1";
        ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";

        AMD_VULKAN_ICD = "RADV";
        ENABLE_GAMESCOPE_WSI = "1";                 # Enable Gamescope WSI layer
        RADV_BUILD_ID_OVERRIDE = "0";               # Disable build ID for shader cache
        RADV_PERFTEST = "sam,dccmsaa,nircache,nggc";
        mesa_glthread = "true";                     # Enable Mesa GL threading
        vblank_mode = "0";                          # Disable VSync at driver level

        # ntsync - NT synchronization primitives for improved Wine/Proton performance
        # Requires kernel 6.10+ with CONFIG_NTSYNC=y and /dev/ntsync device
        WINEFSYNC = "1";                            # Enable ntsync for Wine/Proton
      } // (optionalAttrs cfg.gaming.enable {
        # Esync/Fsync optimizations (work alongside ntsync)
        WINEESYNC = "1";                            # Enable esync as fallback
        PROTON_NO_ESYNC = "0";                      # Ensure esync is not disabled
        PROTON_NO_FSYNC = "0";                      # Ensure fsync is not disabled
      }) // (optionalAttrs (cfg.gaming.enable && cfg.gaming.enableDxvkStateCache) {
        # DXVK optimizations for Vulkan-based D3D9/10/11 translation
        DXVK_HUD = cfg.gaming.dxvkHud;
        DXVK_STATE_CACHE_PATH = "${cfg.gaming.shaderCacheBasePath}/dxvk";
        DXVK_LOG_LEVEL = "warn";
      }) // (optionalAttrs (cfg.gaming.enable && cfg.gaming.enableVkd3dShaderCache) {
        # VKD3D-Proton optimizations for D3D12 -> Vulkan translation
        VKD3D_CONFIG = "dxr11,dxr";                 # Enable DXR (DirectX Raytracing)
        VKD3D_SHADER_CACHE_PATH = "${cfg.gaming.shaderCacheBasePath}/vkd3d";
      }) // (optionalAttrs (cfg.gaming.enable && cfg.gaming.cpuTopology != null) {
        # Override Wine CPU topology detection
        WINE_CPU_TOPOLOGY = cfg.gaming.cpuTopology;
      }) // (optionalAttrs (cfg.gaming.enable && cfg.gaming.enableLargeAddressAware) {
        # Enable large address aware for 32-bit games
        PROTON_FORCE_LARGE_ADDRESS_AWARE = "1";
      }) // (optionalAttrs (cfg.gaming.enable && cfg.gaming.gpuVendor == "amd") {
        # AMD-specific optimizations
        PROTON_ENABLE_NVAPI = "0";                  # Disable NVIDIA API
        PROTON_HIDE_NVIDIA_GPU = "1";               # Hide NVIDIA GPU detection
      }) // (optionalAttrs (cfg.gaming.enable && cfg.gaming.gpuVendor == "nvidia") {
        # NVIDIA-specific optimizations
        PROTON_ENABLE_NVAPI = "1";                  # Enable NVIDIA API
        __GL_SHADER_DISK_CACHE = "1";               # Enable NVIDIA shader cache
        __GL_SHADER_DISK_CACHE_PATH = "${cfg.gaming.shaderCacheBasePath}/nvidia";
      }) // (optionalAttrs cfg.lsfg.enable {
        LSFG_DLL_PATH = "\${HOME}/.local/share/Steam/steamapps/common/Lossless\ Scaling/Lossless.dll";
      });
    };

    hardware = {
      ksm.enable = true;

      bluetooth.settings = mkMerge [
        # Base Bluetooth settings - always enabled when desktop module is active
        {
          General = {
            ControllerMode = "dual";  # Both BR/EDR and LE
            FastConnectable = cfg.bluetooth.enableFastConnectable;
            JustWorksRepairing = "always";  # Allow re-pairing without user confirmation
            MultiProfile = "multiple";  # Support multiple profiles and devices
          };

          Policy = {
            ReconnectAttempts = cfg.bluetooth.reconnectAttempts;
            ReconnectIntervals = builtins.concatStringsSep "," (map toString cfg.bluetooth.reconnectIntervals);
            AutoEnable = true;  # Auto-enable Bluetooth adapters
          };
        }

        # Low-latency optimizations for gaming, VoIP, and real-time communication
        (mkIf cfg.bluetooth.optimizeForLowLatency {
          General = {
            # Reduce discoverable timeout for security
            DiscoverableTimeout = 120;  # 2 minutes instead of default 3
          };

          LE = {
            # Optimize Low Energy connection parameters for lower latency
            MinConnectionInterval = 6;   # 7.5ms (6 * 1.25ms)
            MaxConnectionInterval = 12;  # 15ms (12 * 1.25ms)
            ConnectionLatency = 0;       # No latency tolerance
            ConnectionSupervisionTimeout = 200;  # 2 seconds
          };

          GATT = {
            # Optimize GATT for better performance
            Cache = "always";  # Enable attribute caching
            ExchangeMTU = 517;  # Maximum MTU for better throughput
          };
        })
      ];

      graphics = {
        enable = true;
        # Use unstable Mesa for better RDNA 4 support
        package = pkgs.unstable.mesa;
        package32 = pkgs.unstable.pkgsi686Linux.mesa;

        # VA-API hardware video acceleration
        extraPackages = with pkgs; [
          libva
          libva-utils
          libva-vdpau-driver
        ];

        extraPackages32 = with pkgs.pkgsi686Linux; [
          libva
          libva-vdpau-driver
        ];
      };
    };

    programs = {
      zsh.enable = true;

      gamemode = mkIf cfg.gaming.enable {
        enable = true;
        settings = mkMerge [
          {
            general = {
              reaper_freq = 5;
              defaultgov = "powersave";
              desiredgov = "performance";
              igpu_desiredgov = "powersave";
              igpu_power_threshold = "0.3";
              softrealtime = "auto";
              renice = 10;
              ioprio = 0;
              inhibit_screensaver = 1;
              disable_splitlock = 1;
            };

            cpu = {
              pin_cores = "yes";
            };

            custom = {
              start = "${pkgs.libnotify}/bin/notify-send 'GameMode started'";
              end = "${pkgs.libnotify}/bin/notify-send 'GameMode ended'";
            };
          }

          (mkIf (cfg.gaming.gpuVendor == "amd") {
            gpu = {
              apply_gpu_optimisations = "accept-responsibility";
              gpu_device = cfg.gaming.gpuDevice;
              amd_performance_level = "high";
            };
          })

          (mkIf (cfg.gaming.gpuVendor == "nvidia") {
            gpu = {
              apply_gpu_optimisations = "accept-responsibility";
              gpu_device = cfg.gaming.gpuDevice;
              nv_powermizer_mode = 1;
            };
          })
        ];
      };

      steam = mkIf cfg.gaming.enable {
        enable = true;
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
      };
    };

    networking = {
      wireless.iwd.settings = mkMerge [
        # Base iwd settings - always enabled when desktop module is active
        {
          General = {
            EnableNetworkConfiguration = true;
          };

          DriverQuirks = {
            DefaultInterface = true;
          };

          Scan = {
            DisablePeriodicScan = false;
          };
        }

        # Low-latency optimizations for gaming, VoIP, and real-time communication
        (mkIf cfg.wifi.optimizeForLowLatency {
          General = {
            # More aggressive roaming for better connection quality
            RoamThreshold = cfg.wifi.roamThreshold;
            RoamThreshold5G = cfg.wifi.roamThreshold5G;
          };

          DriverQuirks = {
            # Disable power save to reduce latency
            PowerSaveDisable = "*";
          };

          Rank = {
            # Prefer 5GHz and 6GHz bands for lower latency
            BandModifier5GHz = cfg.wifi.bandModifier5GHz;
            BandModifier6GHz = cfg.wifi.bandModifier6GHz;
          };
        })
      ];
    };

    security = {
      polkit = {
        enable = true;
      };

      rtkit = {
        enable = true;
      };

      soteria = {
        enable = true;
      };
    };

    services = {
      ananicy = {
        enable = true;
        package = pkgs.ananicy-cpp;
        rulesProvider = pkgs.ananicy-rules-cachyos;
      };

      cachix-watch-store = {
        cacheName = "ajenkins-public";
        cachixTokenFile = "/persistence/cachix/authToken";
        compressionLevel = 5;
        enable = false;
        jobs = 4;
      };

      colord = {
        enable = true;
      };

      desktopManager.cosmic = mkIf cfg.cosmic.enable {
        enable = true;
      };

      gvfs = {
        enable = true;
      };

      tumbler = {
        enable = true;
      };

      udisks2 = {
        enable = true;
      };

      lsfg-vk = {
        enable = cfg.lsfg.enable;
        package = pkgs.lsfg-vk-ui;
      };

      pulseaudio = {
        enable = false;
      };

      pipewire = {
        alsa.enable = true;
        alsa.support32Bit = true;
        enable = true;
        jack.enable = true;
        pulse.enable = true;

        audio = {
          enable = true;
        };

        extraConfig = {
          pipewire = {
            "10-clock-rate" = {
              "context.properties" = {
                "default.clock.allowed-rates" = cfg.pipewire.allowedSampleRates;
              };
            };
            "10-quantum" = let
              quantum = cfg.pipewire.quantum;
              minQuantum = if cfg.pipewire.minQuantum != null then cfg.pipewire.minQuantum else quantum;
              maxQuantum = if cfg.pipewire.maxQuantum != null then cfg.pipewire.maxQuantum else quantum;
              quantumStr = builtins.toString quantum;
              minQuantumStr = builtins.toString minQuantum;
              maxQuantumStr = builtins.toString maxQuantum;
            in {
              "context.properties" = {
                "default.clock.quantum" = quantum;
                "default.clock.min-quantum" = minQuantum;
                "default.clock.max-quantum" = maxQuantum;
              };
              "pulse.properties" = {
                "pulse.min.req" = "${minQuantumStr}/48000";
                "pulse.default.req" = "${quantumStr}/48000";
                "pulse.max.req" = "${maxQuantumStr}/48000";
                "pulse.min.quantum" = "${minQuantumStr}/48000";
                "pulse.max.quantum" = "${maxQuantumStr}/48000";
              };
              "stream.properties" = {
                "node.latency" = "${quantumStr}/48000";
                "resample.quality" = cfg.pipewire.resampleQuality;
              };
            };
            "10-alsa-headroom" = {
              "context.properties" = {
                "api.alsa.headroom" = cfg.pipewire.alsaHeadroom;
              };
            };
          };
        };

        wireplumber = {
          enable = true;

          configPackages = [
            # Bluetooth codec configuration
            (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/51-bluez-config.conf" ''
              monitor.bluez.properties = {
                bluez5.roles = [ a2dp_sink a2dp_source bap_sink bap_source hsp_hs hsp_ag hfp_hf hfp_ag ]
                bluez5.codecs = [ ${builtins.concatStringsSep " " cfg.bluetooth.audioCodecPriority} ]
                bluez5.default.rate = ${toString cfg.bluetooth.defaultSampleRate}
                bluez5.default.channels = 2
                bluez5.a2dp.ldac.quality = "${cfg.bluetooth.ldacQuality}"
                bluez5.enable-sbc-xq = true
                bluez5.enable-msbc = true
                bluez5.enable-hw-volume = true
                bluez5.hw-volume = [ hfp_hf hsp_hs a2dp_sink ]
              }

              monitor.bluez.rules = [
                {
                  matches = [
                    {
                      device.name = "~bluez_card.*"
                    }
                  ]
                  actions = {
                    update-props = {
                      api.bluez5.auto-connect = [ hfp_hf hsp_hs a2dp_sink ]
                      bluez5.auto-connect = true
                    }
                  }
                }
              ]
            '')
          ] ++ (optionals (cfg.pipewire.suspendTimeoutSeconds > 0) [
            (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/51-suspend-on-idle.conf" ''
              monitor.alsa.rules = [
                {
                  matches = [
                    {
                      node.name = "~alsa_output.*"
                    }
                    {
                      node.name = "~alsa_input.*"
                    }
                  ]
                  actions = {
                    update-props = {
                      session.suspend-timeout-seconds = ${toString cfg.pipewire.suspendTimeoutSeconds}
                    }
                  }
                }
              ]
            '')
          ]) ++ [
            # Per-device quantum/latency rules for optimal performance
            (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/52-device-latency.conf" ''
              # Low-latency settings for wired ALSA audio devices
              monitor.alsa.rules = [
                {
                  matches = [
                    { node.name = "~alsa_output.*" }
                  ]
                  actions = {
                    update-props = {
                      # Aggressively seek lower quantum for wired audio
                      api.alsa.period-size = ${toString cfg.pipewire.minQuantum}
                      api.alsa.headroom = ${toString cfg.pipewire.alsaHeadroom}
                      node.latency = "${toString cfg.pipewire.minQuantum}/48000"
                    }
                  }
                }
              ]

              # Higher latency for Bluetooth to prevent dropouts
              monitor.bluez.rules = [
                {
                  matches = [
                    { node.name = "~bluez_output.*" }
                    { node.name = "~bluez_input.*" }
                  ]
                  actions = {
                    update-props = {
                      # Use higher quantum for Bluetooth stability
                      node.latency = "${toString cfg.pipewire.quantum}/48000"
                      api.bluez5.a2dp.ldac.quality = "${cfg.bluetooth.ldacQuality}"
                    }
                  }
                }
              ]
            '')
          ];
        };
      };

      power-profiles-daemon = {
        enable = true;
      };

      printing = mkIf cfg.printing.enable {
        enable = true;
      };

      scx = {
        enable = true;
        scheduler = "scx_lavd";
      };

      tlp = {
        enable = false;

        settings = {
        };
      };

      udev = {
        enable = true;

        extraRules = ''
          # AMD GPU performance - let gamemode handle performance levels
          ACTION=="add", SUBSYSTEM=="drm", DRIVERS=="amdgpu", ATTR{device/power_dpm_force_performance_level}="auto"

          # ntsync device permissions for Wine/Proton performance
          KERNEL=="ntsync", MODE="0666"
        '';
      };

      xserver = {
        videoDrivers = [
          "fbdev"
          "modesetting"
        ];
        xkb = {
          layout = "us";
          variant = "";
        };
      };
    };

    fonts = {
      packages = with pkgs; [
        dejavu_fonts
        nerd-fonts.fira-code
        nerd-fonts.hack
        nerd-fonts.jetbrains-mono
        nerd-fonts.noto
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        recursive
        twemoji-color-font
      ];

      fontconfig = {
        localConf = ''
          <?xml version="1.0"?>
          <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
          <fontconfig>
            <!-- Default system-ui fonts -->
            <match target="pattern">
              <test name="family">
                <string>system-ui</string>
              </test>
              <edit name="family" mode="prepend" binding="strong">
                <string>sans-serif</string>
              </edit>
            </match>

            <!-- Default sans-serif fonts-->
            <match target="pattern">
              <test name="family">
                <string>sans-serif</string>
              </test>
              <edit name="family" mode="prepend" binding="strong">
                <string>Noto Sans CJK SC</string>
                <string>Noto Sans</string>
                <string>Twemoji</string>
              </edit>
            </match>

            <!-- Default serif fonts-->
            <match target="pattern">
              <test name="family">
                <string>serif</string>
              </test>
              <edit name="family" mode="prepend" binding="strong">
                <string>Noto Serif CJK SC</string>
                <string>Noto Serif</string>
                <string>Twemoji</string>
              </edit>
            </match>

            <!-- Default monospace fonts-->
            <match target="pattern">
              <test name="family">
                <string>monospace</string>
              </test>
              <edit name="family" mode="prepend" binding="strong">
                <string>Noto Sans Mono CJK SC</string>
                <string>Symbols Nerd Font</string>
                <string>Twemoji</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang">
                <string>zh-HK</string>
              </test>
              <test name="family">
                <string>Noto Sans CJK SC</string>
              </test>
              <edit name="family" binding="strong">
                <string>Noto Sans CJK HK</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang">
                <string>zh-HK</string>
              </test>
              <test name="family">
                <string>Noto Serif CJK SC</string>
              </test>
              <edit name="family" binding="strong">
                <!-- not have HK -->
                <string>Noto Serif CJK TC</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang">
                <string>zh-HK</string>
              </test>
              <test name="family">
                <string>Noto Sans Mono CJK SC</string>
              </test>
              <edit name="family" binding="strong">
                <string>Noto Sans Mono CJK HK</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang">
                <string>zh-TW</string>
              </test>
              <test name="family">
                <string>Noto Sans CJK SC</string>
              </test>
              <edit name="family" binding="strong">
                <string>Noto Sans CJK TC</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang">
                <string>zh-TW</string>
              </test>
              <test name="family">
                <string>Noto Serif CJK SC</string>
              </test>
              <edit name="family" binding="strong">
                <string>Noto Serif CJK TC</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang">
                <string>zh-TW</string>
              </test>
              <test name="family">
                <string>Noto Sans Mono CJK SC</string>
              </test>
              <edit name="family" binding="strong">
                <string>Noto Sans Mono CJK TC</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang">
                <string>ja</string>
              </test>
              <test name="family">
                <string>Noto Sans CJK SC</string>
              </test>
              <edit name="family" binding="strong">
                <string>Noto Sans CJK JP</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang">
                  <string>ja</string>
              </test>
              <test name="family">
                <string>Noto Serif CJK SC</string>
              </test>
              <edit name="family" binding="strong">
                <string>Noto Serif CJK JP</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang">
                <string>ja</string>
              </test>
              <test name="family">
                <string>Noto Sans Mono CJK SC</string>
              </test>
              <edit name="family" binding="strong">
                <string>Noto Sans Mono CJK JP</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang">
                <string>ko</string>
              </test>
              <test name="family">
                <string>Noto Sans CJK SC</string>
              </test>
              <edit name="family" binding="strong">
                <string>Noto Sans CJK KR</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang">
                <string>ko</string>
              </test>
              <test name="family">
                <string>Noto Serif CJK SC</string>
              </test>
              <edit name="family" binding="strong">
                <string>Noto Serif CJK KR</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang">
                <string>ko</string>
              </test>
              <test name="family">
                <string>Noto Sans Mono CJK SC</string>
              </test>
              <edit name="family" binding="strong">
                <string>Noto Sans Mono CJK KR</string>
              </edit>
            </match>

            <!-- Replace monospace fonts -->
            <match target="pattern">
              <test name="family" compare="contains">
                <string>Source Code</string>
              </test>
              <edit name="family" binding="strong">
                <string>Iosevka Term</string>
              </edit>
            </match>
            <match target="pattern">
              <test name="lang" compare="contains">
                <string>en</string>
              </test>
              <test name="family" compare="contains">
                <string>Noto Sans CJK</string>
              </test>
              <edit name="family" mode="prepend" binding="strong">
                <string>Noto Sans</string>
              </edit>
            </match>

            <match target="pattern">
              <test name="lang" compare="contains">
                <string>en</string>
              </test>
              <test name="family" compare="contains">
                <string>Noto Serif CJK</string>
              </test>
              <edit name="family" mode="prepend" binding="strong">
                <string>Noto Serif</string>
              </edit>
            </match>
          </fontconfig>
        '';
      };
    };

    stylix =
      let
        wallpaper = pkgs.fetchurl {
          url = "https://media.githubusercontent.com/media/alisonjenkins/nix-config/8a0e3f667dcc5fe0f2e461ca4cb17c74028d92f8/home/wallpapers/5120x1440/Static/sakura.jpg";
          hash = "sha256-rosIVRieazPxN7xrpH1HBcbQWA/1FYk1gRn1vy6Xe3s=";
        };
      in
      {
        base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
        enable = true;
        image = wallpaper;
        polarity = "dark";

        cursor = {
          package = pkgs.material-cursors;
          name = "material_light_cursors";
          size = 30;
        };

        fonts = {
          serif = {
            package = pkgs.nerd-fonts.fira-code;
            name = "FiraCode Nerd Font Mono";
          };

          sansSerif = {
            package = pkgs.nerd-fonts.fira-code;
            name = "FiraCode Nerd Font Mono";
          };

          monospace = {
            package = pkgs.nerd-fonts.fira-code;
            name = "FiraCode Nerd Font Mono";
          };

          emoji = {
            package = pkgs.noto-fonts-color-emoji;
            name = "Noto Color Emoji";
          };
        };

        homeManagerIntegration = {
          followSystem = true;
        };

        opacity = {
          desktop = 0.0;
          terminal = 0.9;
        };

        targets = {
          nixvim = {
            transparentBackground = {
              main = true;
              signColumn = true;
            };
          };

          qt = {
            enable = false;
          };
        };
      };

    xdg.portal = {
      enable = true;
      xdgOpenUsePortal = true;

      extraPortals = mkDefault (with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-gnome
      ]);

      config = mkDefault {
        common = {
          default = [ "gtk" ];
          "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
        };

        niri = {
          default = [ "gtk" ];
          "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
        };

        hyprland = {
          default = [ "hyprland" "gtk" ];
          "org.freedesktop.impl.portal.FileChooser" = [ "kde" ];
          "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
        };
      };
    };
  };
}
