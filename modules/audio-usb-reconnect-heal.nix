{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.audio-usb-reconnect-heal;

  # Root, because udev rules run as root; pw-link needs the user's PipeWire.
  # `runuser` is deliberately given XDG_RUNTIME_DIR explicitly: neither the
  # `runuser` nor the `runuser-l` PAM stack on NixOS includes pam_systemd, so
  # the child inherits no XDG_RUNTIME_DIR and pw-link cannot find the socket.
  # Without it every call died with "can't connect: Host is down" -- silently,
  # because the failure was redirected away -- so this service never once
  # healed a link between being written and 2026-08-24.
  asUser = "${pkgs.util-linux}/bin/runuser -u ${lib.escapeShellArg cfg.user} -- ${pkgs.coreutils}/bin/env XDG_RUNTIME_DIR=/run/user/\"$uid\"";

  udevRules =
    concatMapStringsSep "\n" (d: ''
      SUBSYSTEM=="usb", ATTR{idVendor}=="${d.vendorId}", ATTR{idProduct}=="${d.productId}", ENV{DEVTYPE}=="usb_device", ACTION=="add", TAG+="systemd", ENV{SYSTEMD_WANTS}+="audio-usb-reconnect-heal.service"
    '')
    cfg.devices;

  # Space-delimited "output-port input-port" pairs, one per line, fed to the
  # relink loop's `read -r out_port in_port` below. Not shell-quoted -- relies
  # on port names (Nix-generated node:port strings) never containing spaces.
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
            description = "Human-readable name, for readability in the config only -- not referenced at runtime.";
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
          uid=$(${pkgs.coreutils}/bin/id -u ${lib.escapeShellArg cfg.user})
          ${pkgs.coreutils}/bin/sleep ${toString cfg.settleSeconds}

          # pw-link is a harmless no-op ("File exists") when the link is
          # already there, so this only ever adds what's missing -- never
          # tears anything down.
          #
          # Three outcomes, deliberately logged differently. A link that was
          # already there is the steady state on almost every run and says
          # nothing worth reading, so it is silent -- logging it as "relinked"
          # made the log claim work that never happened. A link actually made
          # is worth a line, because it means something had come adrift. Any
          # other failure must be loud: it means this service is not doing its
          # job. stderr is carried into all three rather than discarded on
          # success, which is what the comment always claimed and the code did
          # not do.
          while read -r out_port in_port; do
            [ -n "$out_port" ] || continue
            if err=$(${asUser} ${pkgs.pipewire}/bin/pw-link "$out_port" "$in_port" 2>&1); then
              if [ -n "$err" ]; then
                echo "audio-usb-reconnect-heal: linked $out_port -> $in_port: $err"
              else
                echo "audio-usb-reconnect-heal: linked $out_port -> $in_port"
              fi
            else
              case "$err" in
                *"File exists"*) : ;;
                *) echo "audio-usb-reconnect-heal: could not link $out_port -> $in_port: $err" ;;
              esac
            fi
          done <<'EOF'
          ${linkList}
          EOF
        '';
      };
    };
  };
}
