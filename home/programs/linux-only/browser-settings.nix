{ pkgs }:
{
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
    "gfx.canvas.accelerated" = true;
    "gfx.canvas.accelerated.cache-items" = 4096;
    "gfx.canvas.accelerated.cache-size" = 512;
    "image.mem.decode_bytes_at_a_time" = 65536;

    # === Wayland Optimizations (Zero-Copy via DMA-BUF) ===
    "widget.wayland-dmabuf-vaapi.enabled" = true;
    "widget.wayland-dmabuf-webgl.enabled" = true;

    # === WebGL ===
    "webgl.force-enabled" = true;

    # === Cache Settings ===
    "browser.cache.memory.enable" = true;
    "browser.cache.memory.capacity" = 524288;  # 512 MB (let disk cache handle the rest)

    # === Multi-Process & Content Optimization ===
    "browser.preferences.defaultPerformanceSettings.enabled" = false;
    "dom.ipc.processPrelaunch.enabled" = true;
    "browser.tabs.remote.autostart" = true;
    "browser.tabs.remote.force-enable" = true;

    # === Network Settings ===
    "network.prefetch-next" = false;  # More aggressive prefetch, keep disabled
    "network.tcp.fastopen.enable" = true;
    "network.http.max-connections" = 1800;
    "network.http.max-persistent-connections-per-server" = 16;
    "network.dnsCacheExpiration" = 3600;

    # === DNS over HTTPS (Quad9) ===
    "network.trr.mode" = 2;
    "network.trr.uri" = "https://dns11.quad9.net/dns-query";
    "network.trr.custom_uri" = "https://dns11.quad9.net/dns-query";
    "network.trr.excluded-domains" = "pivkm.lan, tower.lan, pikvm.lan, family.google.com";

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

    # === PipeWire Camera Portal ===
    "media.webrtc.camera.allow-pipewire" = true;
  };

  searchEngines = {
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
}
