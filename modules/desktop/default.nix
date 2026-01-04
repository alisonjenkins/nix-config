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

    environment = let
      gamescopeConfig = pkgs.writeTextFile {
        name = "gamescope-config";
        destination = "/usr/share/gamemode/gamescope.ini";

        text = ''
        [general]
        ; The reaper thread will check every 5 seconds for exited clients, for config file changes, and for the CPU/iGPU power balance
        reaper_freq=5

        ; The desired governor is used when entering GameMode instead of "performance"
        desiredgov=performance
        ; The default governor is used when leaving GameMode instead of restoring the original value
        defaultgov=powersave

        ; The desired platform profile is used when entering GameMode instead of "performance"
        desiredprof=performance
        ; The default platform profile is used when leaving GameMode instead of restoring the original value
        ;defaultgov=low-power

        ; The iGPU desired governor is used when the integrated GPU is under heavy load
        igpu_desiredgov=powersave
        ; Threshold to use to decide when the integrated GPU is under heavy load.
        ; This is a ratio of iGPU Watts / CPU Watts which is used to determine when the
        ; integraged GPU is under heavy enough load to justify switching to
        ; igpu_desiredgov.  Set this to -1 to disable all iGPU checking and always
        ; use desiredgov for games.
        igpu_power_threshold=0.3

        ; GameMode can change the scheduler policy to SCHED_ISO on kernels which support it (currently
        ; not supported by upstream kernels). Can be set to "auto", "on" or "off". "auto" will enable
        ; with 4 or more CPU cores. "on" will always enable. Defaults to "off".
        softrealtime=auto

        ; GameMode can renice game processes. You can put any value between 0 and 20 here, the value
        ; will be negated and applied as a nice value (0 means no change). Defaults to 0.
        ; To use this feature, the user must be added to the gamemode group (and then rebooted):
        ; sudo usermod -aG gamemode $(whoami)
        renice=10

        ; By default, GameMode adjusts the iopriority of clients to BE/0, you can put any value
        ; between 0 and 7 here (with 0 being highest priority), or one of the special values
        ; "off" (to disable) or "reset" (to restore Linux default behavior based on CPU priority),
        ; currently, only the best-effort class is supported thus you cannot set it here
        ioprio=0

        ; Sets whether gamemode will inhibit the screensaver when active
        ; Defaults to 1
        inhibit_screensaver=1

        ; Sets whether gamemode will disable split lock mitigation when active
        ; Defaults to 1
        disable_splitlock=1

        [filter]
        ; If "whitelist" entry has a value(s)
        ; gamemode will reject anything not in the whitelist
        ;whitelist=RiseOfTheTombRaider

        ; Gamemode will always reject anything in the blacklist
        ;blacklist=HalfLife3
        ;    glxgears

        [gpu]
        ; Here Be Dragons!
        ; Warning: Use these settings at your own risk
        ; Any damage to hardware incurred due to this feature is your responsibility and yours alone
        ; It is also highly recommended you try these settings out first manually to find the sweet spots

        ; Setting this to the keyphrase "accept-responsibility" will allow gamemode to apply GPU optimisations such as overclocks
        apply_gpu_optimisations=accept-responsibility

        ; The DRM device number on the system (usually 0), ie. the number in /sys/class/drm/card0/
        gpu_device=0

        ; Nvidia specific settings
        ; Requires the coolbits extension activated in nvidia-xconfig
        ; This corresponds to the desired GPUPowerMizerMode
        ; "Adaptive"=0 "Prefer Maximum Performance"=1 and "Auto"=2
        ; See NV_CTRL_GPU_POWER_MIZER_MODE and friends in https://github.com/NVIDIA/nvidia-settings/blob/master/src/libXNVCtrl/NVCtrl.h
        ;nv_powermizer_mode=1

        ; These will modify the core and mem clocks of the highest perf state in the Nvidia PowerMizer
        ; They are measured as Mhz offsets from the baseline, 0 will reset values to default, -1 or unset will not modify values
        ;nv_core_clock_mhz_offset=0
        ;nv_mem_clock_mhz_offset=0

        ; AMD specific settings
        ; Requires a relatively up to date AMDGPU kernel module
        ; See: https://dri.freedesktop.org/docs/drm/gpu/amdgpu.html#gpu-power-thermal-controls-and-monitoring
        ; It is also highly recommended you use lm-sensors (or other available tools) to verify card temperatures
        ; This corresponds to power_dpm_force_performance_level, "manual" is not supported for now
        amd_performance_level=high

        [cpu]
        ; Parking or Pinning can be enabled with either "yes", "true" or "1" and disabled with "no", "false" or "0".
        ; Either can also be set to a specific list of cores to park or pin, comma separated list where "-" denotes
        ; a range. E.g "park_cores=1,8-15" would park cores 1 and 8 to 15.
        ; The default is uncommented is to disable parking but enable pinning. If either is enabled the code will
        ; currently only properly autodetect Ryzen 7900x3d, 7950x3d and Intel CPU:s with E- and P-cores.
        ; For Core Parking, user must be added to the gamemode group (not required for Core Pinning):
        ; sudo usermod -aG gamemode $(whoami)
        ;park_cores=no
        pin_cores=yes

        [supervisor]
        ; This section controls the new gamemode functions gamemode_request_start_for and gamemode_request_end_for
        ; The whilelist and blacklist control which supervisor programs are allowed to make the above requests
        ;supervisor_whitelist=
        ;supervisor_blacklist=

        ; In case you want to allow a supervisor to take full control of gamemode, this option can be set
        ; This will only allow gamemode clients to be registered by using the above functions by a supervisor client
        ;require_supervisor=0

        [custom]
        ; Custom scripts (executed using the shell) when gamemode starts and ends
        ;start=notify-send "GameMode started"
        ;    /home/me/bin/stop_foldingathome.sh

        ;end=notify-send "GameMode ended"
        ;    /home/me/bin/start_foldingathome.sh

        ; Timeout for scripts (seconds). Scripts will be killed if they do not complete within this time.
        ;script_timeout=10
        '';
      };
    in {
      systemPackages = with pkgs; [
        # unstable.winboat
        aider-chat-full
        bluetooth-connect
        deepfilternet
        file-roller
        gamescopeConfig
        hicolor-icon-theme
        lock-session
        millisecond
        nix-flake-template-init
        oxker
        pciutils
        playerctl
        popsicle
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
        wallpapers
        wleave
        zoom-us
      ] ++ (optionals cfg.gaming.enable (with pkgs; [
        boilr
        gamemode
        mangohud
        steamtinkerlaunch
        unstable.goverlay
        unstable.heroic-unwrapped
        unstable.protonplus
        unstable.umu-launcher
      ]))
      ++ (optionals cfg.lsfg.enable [
        inputs.lsfg-vk-flake.packages.${pkgs.stdenv.hostPlatform.system}.lsfg-vk-ui
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
      } // (optionalAttrs cfg.lsfg.enable {
        LSFG_DLL_PATH = "\${HOME}/.local/share/Steam/steamapps/common/Lossless\ Scaling/Lossless.dll";
      });
    };

    hardware = {
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
        settings = {
          general = {
            defaultgov = "powersave";
            desiredgov = "performance";
            softrealtime = "auto";
            ioprio = 0;
            renice = 10;
          };

          custom = {
            start = "${pkgs.libnotify}/bin/notify-send 'GameMode started'";
            end = "${pkgs.libnotify}/bin/notify-send 'GameMode ended'";
          };
        };
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

      desktopManager.cosmic = mkIf cfg.cosmic.enable {
        enable = true;
      };

      lsfg-vk = {
        enable = cfg.lsfg.enable;
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
                "default.clock.allowed-rates" = [44100 48000 88200 96000];
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
          ]);
        };
      };

      power-profiles-daemon = {
        enable = true;
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

    stylix =
      let
        wallpaper = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/alisonjenkins/nix-config/refs/heads/main/home/wallpapers/5120x1440/Static/sakura.jpg";
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
