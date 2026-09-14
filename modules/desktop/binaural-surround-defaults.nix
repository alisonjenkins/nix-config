# Pure, host-independent defaults for
# `modules.desktop.pipewire.binauralSurround.{angles,compensationEq}`.
#
# Factored out of modules/desktop/default.nix so `positional-audio-bench`'s
# `nix flake check` regression gate (flake-modules/positional-audio-bench.nix)
# can import the exact same values without evaluating a full host — no
# hand-copied numbers, and no dependency on host-specific config (secrets,
# hardware-gated requireFiles) that would make the check flaky or slow.
{
  angles = {
    FL = 30;
    FR = 330;
    FC = 0;
    LFE = 0;
    RL = 150;
    RR = 210;
    SL = 90;
    SR = 270;
  };

  # The default is unmeasured (no coloration to compensate for yet) — a real
  # 9-band curve lives per-host, e.g. flake-modules/hosts/ali-desktop/default.nix,
  # derived from that host's own measurement. The regression gate scores the
  # raw HRIR geometry against these defaults; tuning a host's real EQ is done
  # via `positional-audio-bench tune --host <name>`, not this file.
  compensationEq = [ ];
}
