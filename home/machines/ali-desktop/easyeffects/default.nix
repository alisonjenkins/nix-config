{
  config,
  pkgs,
  lib,
  ...
}: let
  profilesDir = ./profiles;

  profileFiles =
    if builtins.pathExists profilesDir
    then
      lib.filterAttrs
      (name: type: type == "regular" && lib.hasSuffix ".json" name)
      (builtins.readDir profilesDir)
    else {};

  profileFileAttrs = lib.mapAttrs' (
    filename: _:
      lib.nameValuePair
      ".config/easyeffects/output/${filename}"
      {source = profilesDir + "/${filename}";}
  ) profileFiles;
in {
  home.packages = [pkgs.easyeffects];

  home.file =
    profileFileAttrs
    // {
      ".config/easyeffects/output/.keep".text = "";

      # EasyEffects input chain ends up emitting voice on the LEFT channel
      # only: one of the stacked denoisers (deepfilternet / rnnoise) processes
      # in mono and zeros the right channel of easyeffects_source. That dead
      # right channel rides through to Zen/Element so remote listeners hear
      # voice in one ear. (The Scarlett mic itself is fine — it shows up on
      # both raw capture channels; the chain is where FR gets dropped.)
      #
      # Fix: a PipeWire loopback that captures the surviving left channel of
      # easyeffects_source as a single (FL) channel and re-renders it to a
      # stereo (FL+FR) virtual source "mic_zen_mono", duplicating the processed
      # voice into both channels. Zen is then routed to this node (see the
      # WirePlumber rule below) so callers hear voice in both ears.
      #
      # Channel counts are asymmetric on purpose: capture is 1ch [FL] so it
      # links to the source's FL at unity (no -6 dB downmix-averaging of the
      # dead FR), playback is 2ch [FL FR] so the remixer upmixes the mono
      # stream by duplicating it into both channels. Do NOT set
      # stream.dont-remix here — the upmix IS the remix we want, and disabling
      # it leaves the capture/playback channel counts unlinked (silent).
      ".config/pipewire/pipewire.conf.d/91-mic-zen-mono.conf".text = ''
        context.modules = [
          {
            name = libpipewire-module-loopback
            args = {
              node.description = "Mic for Zen (Mono)"
              capture.props = {
                node.name      = "mic_zen_capture"
                node.target    = "easyeffects_source"
                audio.channels = 1
                audio.position = [ FL ]
                node.passive   = true
              }
              playback.props = {
                node.name        = "mic_zen_mono"
                node.description = "Mic for Zen (Mono)"
                media.class      = "Audio/Source/Virtual"
                audio.channels   = 2
                audio.position   = [ FL FR ]
              }
            }
          }
        ]
      '';

      # Force Zen browser mic input to use the processed, stereo-duplicated
      # mic_zen_mono source (easyeffects_source -> mono -> FL+FR loopback
      # above) instead of the raw Scarlett ALSA capture. Without this,
      # WirePlumber's default-policy auto-links Zen to the raw mic *in addition
      # to* the processed source, so remote listeners hear raw voice + delayed
      # processed voice = echo. Targeting mic_zen_mono also fixes the dead
      # right channel (see loopback comment above). Local recording tools
      # (Audacity) read the raw capture directly and don't surface the issue.
      ".config/wireplumber/wireplumber.conf.d/90-zen-mic-route.conf".text = ''
        node.rules = [
          {
            matches = [
              {
                application.name = "Zen"
                media.class = "Stream/Input/Audio"
              }
            ]
            actions = {
              update-props = {
                target.object = "mic_zen_mono"
              }
            }
          }
        ]
      '';
    };
}
