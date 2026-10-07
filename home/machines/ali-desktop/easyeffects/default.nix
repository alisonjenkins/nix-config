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

  # EasyEffects 8.x reads presets from ~/.local/share/easyeffects/, not
  # ~/.config/easyeffects/ (the 7.x path) -- confirmed via a stronger-model
  # consult while debugging an unrelated mic issue tonight; the installed
  # version here is 8.2.4.
  profileFileAttrs = lib.mapAttrs' (
    filename: _:
      lib.nameValuePair
      ".local/share/easyeffects/output/${filename}"
      {source = profilesDir + "/${filename}";}
  ) profileFiles;
in {
  home.packages = [pkgs.easyeffects];

  # EasyEffects' output chain here has no effects, only meters: it just hands
  # every app on to the binaural sink, which is the default sink anyway. While
  # it grabs every output stream it also took games back off the Remote Play
  # sink, about once a second; each move re-links the stream, the likely cause
  # of an occasional crackle (2026-10-07). Inputs (the mic noise
  # cancellation) are a separate setting and stay on. Set in place because
  # EasyEffects owns and rewrites this file, and read only when it starts, so
  # restart it once after the first switch.
  home.activation.easyeffectsLeaveOutputsAlone = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
      --file "${config.xdg.configHome}/easyeffects/db/easyeffectsrc" \
      --group EffectsPipelines --key processAllOutputs false
  '';

  home.file =
    profileFileAttrs
    // {
      ".local/share/easyeffects/output/.keep".text = "";

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
