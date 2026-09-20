{ config, lib, pkgs, ... }:
let
  cfg = config.modules.vr;

  pactl = "${pkgs.pulseaudio}/bin/pactl";
  pw-link = "${pkgs.pipewire}/bin/pw-link";

  # Space-delimited "output-port input-port" pairs, one per line, matching
  # the format services.audio-usb-reconnect-heal uses for the same purpose.
  extraRelinkList = lib.concatMapStringsSep "\n" (l: "${l.output} ${l.input}") cfg.extraRelinkPorts;

  # Script that watches PipeWire for wivrn.sink appearing/disappearing.
  # On connect: links the audio sink's monitor to wivrn.sink so audio plays
  #             on both local output and VR headset, and switches default
  #             source to headset mic.
  #             Prefers easyeffects_sink if available, otherwise uses default sink.
  # On disconnect: removes links, restores default source.
  wivrnAudioScript = pkgs.writeShellScript "wivrn-audio-monitor" ''
    LINKED=false
    AUDIO_SINK=""

    has_wivrn_sink() {
      ${pactl} list short sinks 2>/dev/null | grep -q 'wivrn\.sink'
    }

    has_wivrn_source() {
      ${pactl} list short sources 2>/dev/null | grep -q 'wivrn\.source'
    }

    # Find the best sink to link: prefer easyeffects_sink, fall back to default
    find_audio_sink() {
      if ${pw-link} -o 2>/dev/null | grep -q '^easyeffects_sink:monitor_'; then
        echo "easyeffects_sink"
      else
        ${pactl} get-default-sink 2>/dev/null
      fi
    }

    cleanup() {
      if $LINKED && [ -n "$AUDIO_SINK" ]; then
        ${pw-link} -d "$AUDIO_SINK:monitor_FL" "wivrn.sink:playback_FL" 2>/dev/null || true
        ${pw-link} -d "$AUDIO_SINK:monitor_FR" "wivrn.sink:playback_FR" 2>/dev/null || true
        LINKED=false
      fi
      local alsa_source
      alsa_source="$(${pactl} list short sources 2>/dev/null | grep -m1 'alsa_input\.' | cut -f2)" || true
      if [ -n "''${alsa_source:-}" ]; then
        ${pactl} set-default-source "$alsa_source" 2>/dev/null || true
      fi
    }

    trap cleanup EXIT

    # WiVRn sink/source appearing or disappearing churns PipeWire nodes fast
    # enough to race WirePlumber's own policy linker, which can drop an
    # unrelated dont-reconnect-pinned link elsewhere in the graph (seen
    # 2026-09-20: an EasyEffects filter chain's input link died this way,
    # killing all desktop audio, and nothing else was watching for it).
    # pw-link is a no-op when the link already exists, so this is safe to
    # run after every WiVRn sink/source appear/disappear.
    reassert_extra_links() {
      # Terminator and payload must stay flush left: this function is nested
      # inside the outer script, whose least-indented line sets this whole
      # multi-line string's dedent amount to 0, so anything indented here
      # would survive Nix's dedent and break heredoc termination.
      while read -r out_port in_port; do
        [ -n "$out_port" ] || continue
        ${pw-link} "$out_port" "$in_port" 2>/dev/null || true
      done <<'EXTRALINKS'
${extraRelinkList}
EXTRALINKS
    }

    setup_vr_audio() {
      AUDIO_SINK="$(find_audio_sink)"
      if [ -z "$AUDIO_SINK" ]; then
        echo "No audio sink found, skipping link setup"
        return
      fi
      echo "Linking $AUDIO_SINK monitor -> wivrn.sink"
      ${pw-link} "$AUDIO_SINK:monitor_FL" "wivrn.sink:playback_FL" 2>/dev/null || true
      ${pw-link} "$AUDIO_SINK:monitor_FR" "wivrn.sink:playback_FR" 2>/dev/null || true
      LINKED=true
      echo "Links created"

      if has_wivrn_source; then
        ${pactl} set-default-source wivrn.source 2>/dev/null || true
        echo "Set wivrn.source as default microphone"
      fi
    }

    teardown_vr_audio() {
      if $LINKED && [ -n "$AUDIO_SINK" ]; then
        ${pw-link} -d "$AUDIO_SINK:monitor_FL" "wivrn.sink:playback_FL" 2>/dev/null || true
        ${pw-link} -d "$AUDIO_SINK:monitor_FR" "wivrn.sink:playback_FR" 2>/dev/null || true
        LINKED=false
        AUDIO_SINK=""
        echo "Links removed"
      fi
      local alsa_source
      alsa_source="$(${pactl} list short sources 2>/dev/null | grep -m1 'alsa_input\.' | cut -f2)" || true
      if [ -n "''${alsa_source:-}" ]; then
        ${pactl} set-default-source "$alsa_source" 2>/dev/null || true
      fi
    }

    # Check if wivrn.sink already exists at startup
    if has_wivrn_sink; then
      echo "WiVRn sink already present, setting up audio"
      sleep 1
      setup_vr_audio
    fi

    # Read events from pactl subscribe using process substitution
    # so the while loop runs in the main shell (preserving LINKED state)
    while read -r line; do
      case "$line" in
        *"'new'"*sink*)
          if has_wivrn_sink && ! $LINKED; then
            echo "WiVRn sink appeared"
            sleep 1
            setup_vr_audio
          fi
          reassert_extra_links
          ;;
        *"'remove'"*sink*)
          if $LINKED && ! has_wivrn_sink; then
            echo "WiVRn sink disappeared"
            teardown_vr_audio
          fi
          reassert_extra_links
          ;;
        *"'new'"*source*)
          if has_wivrn_source; then
            echo "WiVRn source appeared — switching default mic"
            ${pactl} set-default-source wivrn.source 2>/dev/null || true
          fi
          reassert_extra_links
          ;;
        *"'remove'"*source*)
          if ! has_wivrn_source; then
            alsa_source="$(${pactl} list short sources 2>/dev/null | grep -m1 'alsa_input\.' | cut -f2)" || true
            if [ -n "''${alsa_source:-}" ]; then
              echo "WiVRn source disappeared — restoring default mic"
              ${pactl} set-default-source "$alsa_source" 2>/dev/null || true
            fi
          fi
          reassert_extra_links
          ;;
      esac
    done < <(${pactl} subscribe 2>/dev/null)
  '';
in
{
  options.modules.vr = {
    enable = lib.mkEnableOption "VR support";
    enableOpenSourceVR = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable open source VR stack (Envision + WiVRn)";
    };
    enableEnvision = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Envision GUI for managing OpenXR/Monado (large closure, not required for WiVRn)";
    };
    scale = lib.mkOption {
      type = lib.types.float;
      default = 0.8;
      description = "Foveated rendering scale (lower = less GPU load, reduced peripheral clarity)";
    };
    bitrate = lib.mkOption {
      type = lib.types.int;
      default = 50000000;
      description = "Streaming bitrate in bits per second";
    };
    codec = lib.mkOption {
      type = lib.types.enum [ "h264" "h265" "av1" ];
      default = "h265";
      description = "Video codec for streaming (av1 is more efficient but requires RDNA 3+)";
    };
    encoders = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [
        {
          encoder = "vaapi";
          codec = "h265";
          width = 1.0;
          height = 0.5;
          offset_x = 0.0;
          offset_y = 0.0;
        }
        {
          encoder = "vaapi";
          codec = "h265";
          width = 1.0;
          height = 0.5;
          offset_x = 0.0;
          offset_y = 0.5;
        }
      ];
      description = "Encoder configuration (split into slices for parallel encoding)";
    };
    extraRelinkPorts = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          output = lib.mkOption {
            type = lib.types.str;
            description = "Source port, as `node:port`.";
          };
          input = lib.mkOption {
            type = lib.types.str;
            description = "Destination port, as `node:port`.";
          };
        };
      });
      default = [];
      description = ''
        PipeWire port links to reassert (idempotent `pw-link`, no-op if
        already present) whenever the WiVRn audio monitor sees a WiVRn
        sink or source appear or disappear. WiVRn's headset connect/
        disconnect churns nodes fast enough to race WirePlumber's policy
        linker and drop an unrelated link elsewhere in the graph.
      '';
    };
    steamLibraryRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/home/*/.local/share/Steam" ];
      description = ''
        Glob roots to search for a SteamVR install
        (`steamapps/common/SteamVR`), used to grant `vrcompositor-launcher`
        `cap_sys_nice` so SteamVR's own setup step is a no-op. Extend per
        host with any additional Steam library folder (e.g. a second drive)
        Steam is configured to install into.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [
        pkgs.unstable.bs-manager
        pkgs.unstable.wayvr
        pkgs.xr-video-player
      ];

      # SteamVR's own bin/vrsetup.sh checks vrcompositor-launcher for
      # cap_sys_nice (needed for async reprojection) and, if missing, shows
      # "SteamVR requires superuser access to finish setup" and runs
      # `pkexec setcap CAP_SYS_NICE=eip`. That fails every time here (no
      # polkit agent answers pkexec from inside Steam's pressure-vessel
      # relaunch), so SteamVR reports "setup is incomplete" and Steam Link
      # from the Quest sees SteamVR as not installed properly.
      #
      # Pre-granting the capability outside the sandbox makes vrsetup.sh's
      # own getcap check pass and skip pkexec entirely. Using `+ep` rather
      # than Valve's own `=eip` is deliberate: the inheritable flag in `eip`
      # is what triggers a known vrcompositor crash/graphics-reset bug
      # (nixpkgs#92798, ValveSoftware/SteamVR-for-Linux#440), and `ep` alone
      # still reads as "has cap_sys_nice" to vrsetup.sh's substring check.
      systemd.services.steamvr-setcap = {
        description = "Grant SteamVR's vrcompositor-launcher cap_sys_nice";
        # No RemainAfterExit: a systemd.path trigger issues a plain `start`,
        # which is a no-op on an already-active(exited) unit, so re-running
        # after a Steam update needs this unit back to inactive once done.
        serviceConfig.Type = "oneshot";
        script = ''
          shopt -s nullglob
          # Root patterns as a bash array, one per Nix list entry, so a root
          # containing a space (e.g. "/media/Steam Games/Steam") survives as
          # one token; word-splitting only re-applies where `*` legitimately
          # needs to glob-expand, when filling $launchers below.
          patterns=(
          ${lib.concatMapStringsSep "\n" (root:
            "  ${lib.escapeShellArg "${root}/steamapps/common/SteamVR/bin/linux64/vrcompositor-launcher"}"
          ) cfg.steamLibraryRoots}
          )
          launchers=()
          for pattern in "''${patterns[@]}"; do
            launchers+=( $pattern )
          done
          for launcher in "''${launchers[@]}"; do
            if ! ${pkgs.libcap}/bin/getcap "$launcher" | grep -q cap_sys_nice; then
              ${pkgs.libcap}/bin/setcap cap_sys_nice+ep "$launcher"
            fi
          done
        '';
        wantedBy = [ "multi-user.target" ];
      };

      # Re-runs the grant whenever SteamVR (re)installs vrcompositor-launcher
      # -- a Steam update replaces the binary and drops the capability along
      # with it -- without waiting for the next reboot.
      systemd.paths = lib.listToAttrs (lib.imap0 (i: root: {
        name = "steamvr-setcap-watch-${toString i}";
        value = {
          description = "Watch for a (re)installed SteamVR at ${root}";
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            PathExistsGlob = "${root}/steamapps/common/SteamVR/bin/linux64/vrcompositor-launcher";
            Unit = "steamvr-setcap.service";
          };
        };
      }) cfg.steamLibraryRoots);
    })

    (lib.mkIf (cfg.enable && cfg.enableOpenSourceVR) {
    programs = lib.mkIf cfg.enableEnvision {
      envision = {
        enable = true;
        openFirewall = true;
      };
    };

    # User service that monitors for WiVRn sink and manages audio routing
    systemd.user.services.wivrn-audio = {
      description = "WiVRn audio routing (combine-sink + mic switching)";
      wantedBy = [ "graphical-session.target" ];
      after = [ "pipewire.service" "wireplumber.service" ];
      bindsTo = [ "pipewire.service" ];
      serviceConfig = {
        ExecStart = wivrnAudioScript;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    services = {
      wivrn = {
        enable = true;
        openFirewall = true;
        autoStart = true;
        config = {
          enable = true;

          json = {
            scale = cfg.scale;
            bitrate = cfg.bitrate;
            encoders = cfg.encoders;
          };
        };
      };
    };
  })
  ];
}
