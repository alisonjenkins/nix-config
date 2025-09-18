{ pkgs
, inputs
, pipeWireQuantum ? 256
, enableLSFG ? true
  # , lib
, ...
}: {
  imports = [
    inputs.lsfg-vk-flake.nixosModules.default
    inputs.stylix.nixosModules.stylix
  ];

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
      aider-chat-full
      deepfilternet
      file-roller
      gamescopeConfig
      hicolor-icon-theme
      inputs.caelestia-cli.packages.${system}.default
      oxker
      pciutils
      playerctl
      popsicle
      posting
      powertop
      unstable.easyeffects
      unstable.mission-center
      unstable.nvtopPackages.amd
      wleave
      zoom-us
    ] ++ (if enableLSFG then [
      inputs.lsfg-vk-flake.packages.${system}.lsfg-vk-ui
    ] else []);

    variables = {
      NIXOS_OZONE_WL = "1";
      ZK_NOTEBOOK_DIR = "\${HOME}/git/zettelkasten";
    } // (if enableLSFG then {
      LSFG_DLL_PATH = "\${HOME}/.local/share/Steam/steamapps/common/Lossless\ Scaling/Lossless.dll";
    } else {});
  };

  hardware = {
    graphics = {
      enable = true;
    };
  };

  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
    };
    zsh.enable = true;
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
      cachixTokenFile = "/home/ali/.config/cachix/cachix.dhall";
      compressionLevel = 5;
      enable = true;
      jobs = 4;
    };

    lsfg-vk = {
      enable = enableLSFG;
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
            quantum = pipeWireQuantum;
            quantumStr = builtins.toString pipeWireQuantum;
          in {
            "context.properties" = {
              "default.clock.quantum" = quantum;
              "default.clock.min-quantum" = quantum;
              "default.clock.max-quantum" = quantum;
            };
            "pulse.properties" = {
              "pulse.min.req" = "${quantumStr}/48000";
              "pulse.default.req" = "${quantumStr}/48000";
              "pulse.max.req" = "${quantumStr}/48000";
              "pulse.min.quantum" = "${quantumStr}/48000";
              "pulse.max.quantum" = "${quantumStr}/48000";
            };
            "stream.properties" = {
              "node.latency" = "${quantumStr}/48000";
              "resample.quality" = 1;
            };
          };
        };
      };

      wireplumber = {
        enable = true;
      };
    };

    power-profiles-daemon = {
      enable = false;
    };

    tlp = {
      enable = true;

      settings = {
      };
    };

    udev = {
      enable = true;

      extraRules = ''
        ACTION=="add", SUBSYSTEM=="drm", DRIVERS=="amdgpu", ATTR{device/power_dpm_force_performance_level}="low"
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
  };
}
