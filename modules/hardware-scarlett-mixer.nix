{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.hardware.scarlettMixer;

  setControls = pkgs.writeShellScript "scarlett-mixer-apply" ''
    set -u

    # Resolve the ALSA card index by name -- USB card ordering is not stable.
    card=""
    for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
      card=$(${pkgs.gawk}/bin/awk -v n="${cfg.cardName}" \
        'index($0, n) { print $1; exit }' /proc/asound/cards)
      [ -n "$card" ] && break
      ${pkgs.coreutils}/bin/sleep 1
    done

    if [ -z "$card" ]; then
      echo "scarlett-mixer: card '${cfg.cardName}' not present, nothing to do" >&2
      exit 0
    fi

    ${concatStringsSep "\n" (mapAttrsToList (name: value: ''
        ${pkgs.alsa-utils}/bin/amixer -q -c "$card" sset ${escapeShellArg name} ${toString value} \
          || echo "scarlett-mixer: failed to set ${name}" >&2
      '')
      cfg.controls)}
  '';
in {
  options.hardware.scarlettMixer = {
    enable = mkEnableOption "pinning the Focusrite Scarlett internal mixer to fixed gains";

    cardName = mkOption {
      type = types.str;
      default = "Scarlett 2i2 4th Gen";
      description = "Substring matched against /proc/asound/cards to find the card index.";
    };

    usbVendorId = mkOption {
      type = types.str;
      default = "1235";
      description = "USB idVendor of the interface, used to trigger on hotplug.";
    };

    usbProductId = mkOption {
      type = types.str;
      default = "8219";
      description = "USB idProduct of the interface, used to trigger on hotplug.";
    };

    controls = mkOption {
      type = types.attrsOf types.int;
      default = {
        # The device's internal mixer matrix sits below anything PipeWire can
        # see: PCM 1/2 -> Mixer Input 01/02 -> Monitor Mix A/B -> Analogue Out
        # 1/2. Focusrite ships these gains at -5 dB, which silently costs 5 dB
        # of playback level no matter what PipeWire and the front-panel knob
        # say. 160 is unity (0 dB) on the 0-184 scale; the range tops out at
        # 184 (+6 dB), which would boost above unity and risk clipping.
        #
        # Only the PCM playback path is pinned. Inputs 03/04 are the analogue
        # inputs feeding the monitor mix (hardware mic monitoring), which is a
        # separate concern and is left at whatever the user set.
        "Monitor 1 Mix A Input 01" = 160;
        "Monitor 1 Mix B Input 02" = 160;
        "Monitor 2 Mix A Input 01" = 160;
        "Monitor 2 Mix B Input 02" = 160;
      };
      description = ''
        ALSA mixer controls to pin, as control name -> raw value. Defaults pin
        the PCM playback path to unity gain so that PipeWire is the only
        software volume stage.
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.alsa-utils];

    systemd.services.scarlett-mixer = {
      description = "Pin Focusrite Scarlett internal mixer gains";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        ExecStart = setControls;
      };
    };

    # The interface keeps these settings in its own flash, but a firmware
    # reset, Focusrite Control, or a fresh driver bind can put them back to the
    # factory -5 dB, so reassert them every time the card appears.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="sound", KERNEL=="card*", ATTRS{idVendor}=="${cfg.usbVendorId}", ATTRS{idProduct}=="${cfg.usbProductId}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="scarlett-mixer.service"
    '';
  };
}
