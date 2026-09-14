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
  perSystem = { pkgs, system, ... }:
    let
      defaults = import (self + "/modules/desktop/binaural-surround-defaults.nix");
      configJson = pkgs.writeText "binaural-surround-defaults.json" (builtins.toJSON defaults);
      hrir = "${pkgs.libmysofa}/share/libmysofa/MIT_KEMAR_normal_pinna.sofa";
      # The exact same derivation `nix build .#positional-audio-bench`
      # produces (flake-modules/packages.nix), not a second callPackage of
      # the same source — two independent callPackages against different
      # python3Packages sets (e.g. one pinned to pkgs.unstable, one not)
      # could silently score with different numpy/scipy versions than what
      # users actually run, undermining the whole point of a fixed baseline.
      positional-audio-bench = self.packages.${system}.positional-audio-bench;
    in
    {
      checks.positional-audio-bench = pkgs.runCommand "positional-audio-bench-regress"
        {
          nativeBuildInputs = [ positional-audio-bench ];
        }
        ''
          # Baseline measured on 2026-09-14 with these exact defaults: mean
          # ITD error 3.0 deg, max 15.0 deg @ 105 az/0 el, front-back
          # discrimination 8.6 dB. Thresholds below leave headroom for
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
