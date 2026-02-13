{ lib
, config
, pkgs
, username
, ...
}: {
  config.stylix.targets.zen-browser.profileNames = [
    username
  ];

  config.programs.zen-browser = {
    enable = lib.mkIf pkgs.stdenv.isLinux true;

    profiles.${username} = {
      settings = {
        # === Hardware Video Acceleration (VA-API for AMD RX 7600M XT) ===
        "media.ffmpeg.vaapi.enabled" = true;
        "media.ffvpx.enabled" = true;  # Re-enabled for MSE/HLS.js compatibility
        "media.navigator.mediadatadecoder_vpx_enabled" = true;
        "media.rdd-vpx.enabled" = true;  # Re-enabled for MSE compatibility
        "media.hardware-video-decoding.enabled" = true;
        "media.hardware-video-decoding.force-enabled" = false;  # Allow software fallback for MSE
        "media.eme.enabled" = true;

        # === Media Cache & Buffer Settings (for Jellyfin streaming) ===
        "media.cache_readahead_limit" = 120;  # Read ahead 120 seconds
        "media.cache_resume_threshold" = 60;  # Resume if cached > 60 seconds
        "media.cache_size" = 512000;  # Media cache size in KB (500 MB)
        "media.mediasource.enabled" = true;  # Required for adaptive streaming
        "media.mediasource.webm.enabled" = true;
        "media.mediasource.mp4.enabled" = true;
        "media.autoplay.default" = 0;  # Allow autoplay (0 = allow, 1 = block audio, 5 = block all)
        "media.mkv.enabled" = false;  # Disable MKV DirectPlay, force Jellyfin to use HLS streaming

        # === GPU-Accelerated Rendering ===
        "gfx.webrender.all" = true;
        "gfx.webrender.enabled" = true;
        "gfx.canvas.accelerated" = true;
        "gfx.canvas.accelerated.cache-items" = 4096;
        "gfx.canvas.accelerated.cache-size" = 512;
        "gfx.x11-egl.force-enabled" = true;
        "image.mem.decode_bytes_at_a_time" = 65536;

        # === Compositor Optimizations ===
        "layers.acceleration.force-enabled" = true;
        "layers.gpu-process.enabled" = true;
        "layers.gpu-process.force-enabled" = true;
        "layers.mlgpu.enabled" = true;

        # === Wayland Optimizations (Zero-Copy via DMA-BUF) ===
        "widget.wayland-dmabuf-vaapi.enabled" = true;
        "widget.wayland-dmabuf-webgl.enabled" = true;

        # === WebGL ===
        "webgl.force-enabled" = true;
        "webgl.msaa-force" = true;

        # === Cache Settings ===
        "browser.cache.disk.enable" = false;
        "browser.cache.memory.enable" = true;
        "browser.cache.memory.capacity" = 2147483647;

        # === Multi-Process & Content Optimization ===
        "dom.ipc.processCount" = 8;
        "browser.preferences.defaultPerformanceSettings.enabled" = false;
        "dom.ipc.processPrelaunch.enabled" = true;
        "browser.tabs.remote.autostart" = true;
        "browser.tabs.remote.force-enable" = true;

        # === Network Settings ===
        "network.dns.disablePrefetch" = true;
        "network.http.speculative-parallel-limit" = 0;
        "network.prefetch-next" = false;
        "network.tcp.fastopen.enable" = true;
        "network.http.max-connections" = 1800;
        "network.http.max-persistent-connections-per-server" = 16;
        "network.http.pacing.requests.enabled" = false;
        "network.http.pacing.requests.min-parallelism" = 64;  # Allow more concurrent requests for streaming
        "network.http.throttle.enable" = false;  # Disable request throttling
        "network.dnsCacheExpiration" = 3600;

        # === DNS over HTTPS (Quad9) ===
        "network.trr.mode" = 2;
        "network.trr.uri" = "https://dns11.quad9.net/dns-query";
        "network.trr.custom_uri" = "https://dns11.quad9.net/dns-query";
        "network.trr.excluded-domains" = ", pivkm.lan, tower.lan, pikvm.lan, family.google.com";

        # === Privacy Settings ===
        "dom.security.https_only_mode" = true;
        "privacy.donottrackheader.enabled" = true;
        "privacy.globalprivacycontrol.enabled" = true;

        # === Performance Tuning ===
        "browser.sessionstore.interval" = 60000;
        "accessibility.force_disabled" = 1;
        "accessibility.typeaheadfind.flashBar" = 0;

        # === Developer Tools ===
        "devtools.cache.disabled" = true;
      };

      search.engines = {
        "Nix Packages" = {
          urls = [
            {
              template = "https://search.nixos.org/packages";
              params = [
                {
                  name = "type";
                  value = "packages";
                }
                {
                  name = "query";
                  value = "{searchTerms}";
                }
              ];
            }
          ];
          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = [ "@np" ];
        };
      };
      search.force = true;

      extensions = {
        packages = (
          if pkgs.stdenv.isLinux
          then (with pkgs.nur.repos.rycee.firefox-addons; [
            auto-tab-discard
            darkreader
            firenvim
            libredirect
            link-cleaner
            multi-account-containers
            offline-qr-code-generator
            onepassword-password-manager
            plasma-integration
            privacy-badger
            surfingkeys
            switchyomega
            tab-session-manager
            tree-style-tab
            tst-fade-old-tabs
            tst-indent-line
            tst-tab-search
            ublock-origin
          ])
          else [ ]
        );
      };

      mods = [
        "2317fd93-c3ed-4f37-b55a-304c1816819e"
      ];
    };
  };

  config.home.file =
    if pkgs.stdenv.isLinux then {
      ".local/share/applications/zen-browser.desktop".text = ''
        [Desktop Entry]
        Comment[en_US]=
        Comment=
        Exec=zen
        GenericName[en_US]=
        GenericName=
        Icon=zen
        MimeType=
        Name[en_US]=Zen Browser
        Name=Zen Browser
        Path=
        StartupNotify=true
        Terminal=false
        TerminalOptions=
        Type=Application
        X-KDE-SubstituteUID=false
        X-KDE-Username=
      '';
    } else { };
}
