{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.audio-usb-reconnect-heal;

  # Root, because udev rules run as root; pw-link needs the user's PipeWire.
  asUser = "${pkgs.util-linux}/bin/runuser -u ${cfg.user} --";

  udevRules =
    concatMapStringsSep "\n" (d: ''
      SUBSYSTEM=="usb", ATTR{idVendor}=="${d.vendorId}", ATTR{idProduct}=="${d.productId}", ENV{DEVTYPE}=="usb_device", ACTION=="add", TAG+="systemd", ENV{SYSTEMD_WANTS}+="audio-usb-reconnect-heal.service"
    '')
    cfg.devices;

  # Shell-quoted "output-port input-port" pairs, fed to the relink loop below.
  linkList = concatMapStringsSep "\n" (l: "${l.output} ${l.input}") cfg.expectedLinks;
in {
  options.services.audio-usb-reconnect-heal = {
    enable = mkEnableOption ''
      Self-heal specific PipeWire port links after a tracked USB audio
      device reconnects.

      A USB audio interface that drops and comes back mid-session (e.g.
      behind a USB switch) can leave WirePlumber unable to re-establish
      some of the graph's links -- seen on ali-desktop as the Focusrite
      Scarlett briefly failing to open its ALSA control device, after
      which the link from EasyEffects' virtual sink to the Scarlett's
      hardware playback ports (and from the binaural spatializer into
      EasyEffects) silently never got remade. Everything downstream
      still looked healthy -- unmuted, RUNNING, hw_ptr advancing -- only
      the specific port link was missing, and PipeWire has no facility
      to reassert it on its own.

      This recreates only the named links, with `pw-link`, which is a
      no-op if a link already exists. It deliberately does NOT restart
      wireplumber or any client: that tears down every live PipeWire
      stream, including an in-progress call's audio -- confirmed the
      hard way on 2026-08-19, when restarting wireplumber to fix this
      exact symptom killed a live Zoom call's mic stream mid-session.
    '';

    user = mkOption {
      type = types.str;
      description = "User whose PipeWire session to heal.";
    };

    devices = mkOption {
      description = "USB audio devices to watch for reconnect-induced link loss.";
      default = [];
      example = literalExpression ''
        [
          {
            name = "Focusrite Scarlett 2i2 4th Gen";
            vendorId = "1235";
            productId = "8219";
          }
        ]
      '';
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Human-readable name, used only in log lines.";
          };
          vendorId = mkOption {
            type = types.strMatching "[0-9a-f]{4}";
            description = "USB idVendor, lowercase hex, as printed by lsusb.";
          };
          productId = mkOption {
            type = types.strMatching "[0-9a-f]{4}";
            description = "USB idProduct, lowercase hex, as printed by lsusb.";
          };
        };
      });
    };

    expectedLinks = mkOption {
      description = ''
        PipeWire port links that must exist for audio to reach hardware,
        given as fully-qualified `node:port` pairs (as printed by
        `pw-link -l`). Recreated whenever a tracked device reconnects.
      '';
      default = [];
      example = literalExpression ''
        [
          {
            output = "easyeffects_sink:monitor_FL";
            input = "alsa_output.usb-Focusrite_Scarlett_2i2_4th_Gen_..." + ":playback_FL";
          }
        ]
      '';
      type = types.listOf (types.submodule {
        options = {
          output = mkOption {
            type = types.str;
            description = "Source port, as `node:port`.";
          };
          input = mkOption {
            type = types.str;
            description = "Destination port, as `node:port`.";
          };
        };
      });
    };

    settleSeconds = mkOption {
      type = types.ints.positive;
      default = 5;
      description = "How long to wait after the USB add event before the ports are expected to exist.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.devices != [];
        message = "services.audio-usb-reconnect-heal.devices must list at least one device.";
      }
      {
        assertion = cfg.expectedLinks != [];
        message = "services.audio-usb-reconnect-heal.expectedLinks must list at least one link.";
      }
    ];

    services.udev.extraRules = mkIf (udevRules != "") udevRules;

    systemd.services.audio-usb-reconnect-heal = {
      description = "Recreate PipeWire links dropped by a tracked USB audio device reconnect";

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "audio-usb-reconnect-heal" ''
          set -u
          ${pkgs.coreutils}/bin/sleep ${toString cfg.settleSeconds}

          # pw-link is a harmless no-op ("File exists") when the link is
          # already there, so this only ever adds what's missing -- never
          # tears anything down.
          while read -r out_port in_port; do
            [ -n "$out_port" ] || continue
            ${asUser} ${pkgs.pipewire}/bin/pw-link "$out_port" "$in_port" >/dev/null 2>&1 \
              && echo "audio-usb-reconnect-heal: relinked $out_port -> $in_port" \
              || true
          done <<'EOF'
          ${linkList}
          EOF
        '';
      };
    };
  };
}
