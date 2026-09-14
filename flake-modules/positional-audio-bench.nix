# Regression gate for modules.desktop.pipewire.binauralSurround: fails
# `nix flake check` if the default angles/compensationEq stop matching a
# baseline localization score. Scores the pure defaults
# (modules/desktop/binaural-surround-defaults.nix) against the in-store MIT
# KEMAR SOFA file only — no network fetch, no host eval, so it stays fast and
# hermetic. Tuning a host's actual measured EQ against real/alternate HRIR
# datasets is a manual `positional-audio-bench tune --host <name>` /
# `sweep-datasets` run, not part of this check.
{ self, ... }:
{
  perSystem = { pkgs, ... }:
    let
      defaults = import (self + "/modules/desktop/binaural-surround-defaults.nix");
      configJson = pkgs.writeText "binaural-surround-defaults.json" (builtins.toJSON defaults);
      hrir = "${pkgs.libmysofa}/share/libmysofa/MIT_KEMAR_normal_pinna.sofa";
      # Not sourced from the pkgs/ overlay (self.overlays) — perSystem's
      # default `pkgs` here doesn't have it applied, and this package's own
      # dependencies (python3Packages, makeWrapper, pipewire) are all
      # plain nixpkgs, so callPackage-ing it directly avoids depending on
      # the overlay wiring at all.
      positional-audio-bench = pkgs.callPackage (self + "/pkgs/positional-audio-bench") { };
    in
    {
      checks.positional-audio-bench = pkgs.runCommand "positional-audio-bench-regress"
        {
          nativeBuildInputs = [ positional-audio-bench ];
        }
        ''
          # Baseline measured on 2026-09-14 with these exact defaults: mean
          # ITD error 3.0 deg, max 15.0 deg @ 105 az/0 el, front-back
          # discrimination 8.0 dB. Thresholds below leave headroom for
          # incidental sweep-grid changes while still catching a real
          # regression (e.g. an angles/HRIR change that widens the max error
          # past the 20s, or an EQ that flattens the pinna band toward 0 dB).
          positional-audio-bench regress \
            --config-json ${configJson} \
            --hrir ${hrir} \
            --max-itd-error-deg 20 \
            --min-frontback-score 5.0 \
            --report $out
        '';
    };
}
