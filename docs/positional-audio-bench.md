# positional-audio-bench

Objective localization benchmark for
`modules.desktop.pipewire.binauralSurround` (the virtual 7.1 sink that
binauralises to stereo for headphones, `modules/desktop/default.nix`). It
scores how well the HRTF chain places sound in degrees, instead of relying on
"does this sound right" by ear.

Package: `pkgs/positional-audio-bench`. CLI: `positional-audio-bench`.

## What it measures

For a sweep of azimuths and elevations, the tool synthesizes a test signal,
convolves it against the configured HRIR (Head-Related Impulse Response,
loaded from a SOFA file), applies the configured `compensationEq`, and
extracts three cues from the resulting stereo signal:

- **ITD** (Interaural Time Difference) via GCC-PHAT cross-correlation, scored
  against a Woodworth spherical-head model — the headline "how many degrees
  off" number.
- **ILD** (Interaural Level Difference), a low band and a high band, since ILD
  is frequency-dependent.
- **Front-back discrimination**: the spectral distance, in the 4-10 kHz
  pinna-cue band, between a direction and its front/back mirror. ITD and ILD
  are identical for a direction and its mirror (the "cone of confusion"), so
  this is the only cue that can tell them apart, and it is the one that
  breaks down first when a generic dummy-head HRTF does not match your own
  ears.

**This measures the HRIR's cue content, not what your brain does with it.** A
generic KEMAR HRTF can score well here and still be hard to localize
front-back for you, because pinna shape is individual — the spectral notches
a KEMAR HRIR encodes are KEMAR's, not yours. If `tune` reports decent numbers
but you still cannot place sounds by ear, the fix is a different HRTF
dataset, not more EQ. That is what `sweep-datasets` is for.

## Commands

```sh
nix run .#positional-audio-bench -- tune --host ali-desktop --hrir <path-to.sofa>
```

Prints the full per-angle table plus an aggregate score for one dataset and
config. Use `--config-json <file>` instead of `--host` to score a JSON file
(`{"angles": {...}, "compensationEq": [...]}`) instead of a live host's
config.

```sh
nix run .#positional-audio-bench -- regress \
  --config-json defaults.json --hrir <path.sofa> \
  --max-itd-error-deg 20 --min-frontback-score 5.0
```

Same as `tune`, but exits non-zero if either threshold is violated. This is
what `flake-modules/positional-audio-bench.nix` runs in `nix flake check`,
scored against the pure defaults in
`modules/desktop/binaural-surround-defaults.nix` and the in-store MIT KEMAR
file only, so the check stays hermetic and fast.

```sh
just audio-bench-live ali-desktop <monitor-port-name>
```

Drives the real, running PipeWire chain: plays a test burst into each
channel of the live 7.1 sink and records the actual binauralised output,
instead of simulating the math offline. Needs a live desktop session with
the output device attached. Not part of `nix flake check`.

## Swapping HRTF datasets

`sweep-datasets` scores the same config against several SOFA files and
prints a ranked table:

```sh
nix run .#positional-audio-bench -- sweep-datasets \
  --host ali-desktop \
  --dataset kemar=/nix/store/.../MIT_KEMAR_normal_pinna.sofa \
  --dataset cipic021=/path/to/cipic_subject_021.sofa \
  --dataset mine=/path/to/your_own_measurement.sofa
```

Each `--dataset LABEL=PATH` is a label and a path to a SOFA file. There is no
`pkgs/positional-audio-bench/datasets.nix` fetching alternate datasets yet —
CIPIC, SADIE II, ARI and HUTUBS license terms were not checked before this
was written, so nothing from them is packaged into the Nix store. Get a SOFA
file yourself and point `--dataset` at it:

1. **Pick a closer-matching public dataset.** CIPIC, SADIE II, ARI and HUTUBS
   each publish per-subject SOFA files (CIPIC in particular documents pinna
   size per subject, so you can pick a subject closer to your own ear shape
   than KEMAR's "normal pinna" default). Download the ones you want to try
   and check their license before redistributing them anywhere.
2. **Or measure your own HRTF.** A few university labs and consumer tools
   (e.g. a phone-camera-based estimator, or an in-ear-mic sweep measurement)
   produce a personalized SOFA file. That is the only way to actually match
   your pinna, rather than pick the closest stand-in.
3. **Run `sweep-datasets`** with your candidates alongside the current KEMAR
   file. The front-back discrimination column is the one to watch — a
   personalized or better-matched set should score higher there, not just on
   mean ITD error, which is dominated by head size rather than pinna shape.
4. **Adopt the winner.** Point
   `modules.desktop.pipewire.binauralSurround.hrirFile` at the new SOFA
   file's Nix store path (package it under `pkgs/` the way `libmysofa`'s
   bundled files are referenced today, so the path is reproducible), then
   re-measure `compensationEq` for it — a different HRIR has different
   coloration, so the old EQ curve does not carry over.

## Adding a dataset to the Nix store properly

If a dataset's license allows redistribution and you want it available on
every machine (not just wherever you happened to download it), add a
`fetchurl`/`fetchzip` derivation in a new
`pkgs/positional-audio-bench/datasets.nix`, following the pattern other
fetched packages in this repo use (see `pkgs/lucien/default.nix` or
`pkgs/cavemem/default.nix` for `fetchFromGitHub`/`fetchurl` shape). Confirm
the license permits it first — some of these datasets are research-use-only.

## Known gaps

- No alternate datasets packaged yet (see above).
- The RBJ biquad math in `biquad.py` matches the standard cookbook formulas
  and is unit-tested against its own frequency response, but has not been
  diffed against PipeWire SPA's actual `bq_lowshelf`/`bq_peaking`/
  `bq_highshelf` plugin source. If SPA uses a different Q or gain
  convention, scores would be subtly wrong with no test catching it.
- `live-verify` has not been run against real hardware yet — first use on
  `ali-desktop` is its first real test.

See `PENDING.md` for the same list with more detail.
