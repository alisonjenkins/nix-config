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

      # EasyEffects' mic chain used to emit voice on the LEFT channel only.
      # Looked exactly like a denoiser (deepfilternet / rnnoise) zeroing the
      # right channel, but it wasn't: only XLR/Line Input 1 has a mic
      # connected, and capture channel 2 was routed to DSP 2 -- an empty
      # jack, not the mic. The denoiser was just correctly flooring an
      # already-silent channel to zero. Real fix is at the interface's own
      # internal mixer, below PipeWire entirely -- see `hardware.scarlettMixer`
      # in this host's flake-modules config.
      #
      # Two PipeWire-level workarounds were tried and abandoned before that
      # was found, both via a libpipewire-module-loopback re-exposing
      # easyeffects_source's surviving left channel as a separate virtual mic
      # ("mic_zen_mono"). Both failed badly enough to take down the whole
      # audio session, not just this bug:
      #   1. Mismatched capture/playback channel counts (1ch capture, 2ch
      #      playback, meaning to have the loopback duplicate mono into
      #      stereo) -- the playback node refused to start at all ("start
      #      node error -95: Operation not supported").
      #   2. Symmetric 1ch/1ch (a genuinely mono virtual mic, sidestepping
      #      the duplication question entirely) -- this one is worse: the
      #      node's node-added event silently wedges WirePlumber's
      #      event-dispatcher queue forever, which is processed one event at
      #      a time. Every node-added after it (every app's audio, every
      #      hardware device) queues up behind it and never gets ports or
      #      links -- the entire session goes silently, permanently dead
      #      until pipewire+wireplumber are restarted with this module
      #      removed. Root-caused via a stronger-model consult (event counts:
      #      30 node-added vs 2 session-item-added in a captured
      #      WIREPLUMBER_DEBUG=D log).
    };
}
