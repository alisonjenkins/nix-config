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

**Important limit: this cannot validate a personalized match.** ITD is
scored against an idealized spherical head, and front-back is scored as
"how spectrally distinct is this HRIR's own front vs. back," not "how well
does this HRIR match a specific listener's ears." A genuinely
well-personalized HRTF can legitimately score *lower* here while localizing
better for that one person, because their brain is listening for cues
shaped like their own pinna, not for maximally distinct cues in the
abstract. Use `tune`/`regress`/`sweep-datasets` to compare *generic*
datasets against each other (that comparison is fair — neither side is
tuned to anyone in particular) or to catch broken/corrupted data. To judge
whether a personalized candidate (from `match-subject` or a DIY
measurement) actually helps *you*, use `perceptual-test` instead — nothing
else in this tool can answer that question.

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

```sh
nix run .#positional-audio-bench -- perceptual-test \
  --config-json defaults.json --hrir <path.sofa> --trials 20
```

The actual validation step for any candidate HRIR. Renders test tones at
random compass directions (F/FR/R/BR/B/BL/L/FL — 45° buckets) straight from
the given HRIR/EQ (bypassing the live PipeWire chain entirely, so it works
on any candidate file without deploying it first), plays each through your
headphones via `pw-cat`, and asks you to type the compass code for where it
sounded like it came from. Reports exact-bucket accuracy, mean direction
error, and — the number that matters for the front-back complaint —
front-back confusion rate: how often a front sound was heard as coming from
behind or vice versa. Run it once per candidate (current default, a
`match-subject` result, a DIY measurement) and compare the confusion rates
directly; that comparison is meaningful in a way `sweep-datasets` scores
are not, because it actually asks a human. `--report path.json` saves the
raw per-trial data. Needs headphones and a live PipeWire session; not part
of `nix flake check`.

```sh
nix run .#positional-audio-bench -- match-subject \
  --fossa-height 1.5 --pinna-height 6.4 --pinna-width 2.9
```

Finds the closest-matching real human ear to your own, from the 96-subject
HUTUBS database (see "Personalization" below), by nearest-neighbour
z-scored distance on whichever pinna measurements you provide. Prints the
top 3 matches by HUTUBS subject ID and the `sofacoustics.org` URL to fetch
the winner's SOFA file. `--measure NAME=VALUE` adds any other HUTUBS pinna
parameter (see `positional_audio_bench/subject_match.py`'s
`D_PARAM_NAMES`) if you have calipers rather than just a ruler.

## Personalization: matching your own ears

Swapping between generic dummy-head datasets (see the CIPIC result below)
didn't help — matching pinna *size* to a mannequin isn't the same as
matching pinna *shape* to a real ear. The next lever is a personalized
HRTF, and the cheapest way to test the idea before spending a weekend on a
DIY measurement rig or ~€600 on a commercial service (see `PENDING.md` for
the full feasibility research) is **nearest-neighbour matching**: measure
a few of your own pinna dimensions, find the closest-matching real human in
a public anthropometry database, and try their actual measured HRTF.

1. **Measure.** `match-subject` matches on `fossa_height`, `pinna_height`,
   and `pinna_width` by default — the three HUTUBS pinna parameters large
   enough (population SD 0.3-0.5cm) that a ruler against a straight-on ear
   photo gives a usable reading. The other seven pinna parameters (cavum
   concha height/width/depth, cymba concha height, intertragal incisure,
   crus of helix depth, the two rotation/flare angles) have population SDs
   down around 1-2mm — close to or smaller than home-measurement error, so
   measuring those with household tools is likely to add noise, not
   information, unless you have real calipers. Photograph each ear
   straight-on with a ruler in frame, measure from the photo, average a few
   shots.
2. **Match.** Run `match-subject` with your numbers. It prints the top 3
   HUTUBS subject IDs.
3. **Fetch and sanity-check.** `nix store prefetch-file` the winner's SOFA
   file (URL printed by `match-subject`), then run it through
   `sweep-datasets` — this only catches broken/corrupted data, it does not
   tell you whether the match will actually sound better (see the limit
   above).
4. **Actually validate.** Run `perceptual-test` against the matched
   subject's file, then again against your current default, and compare
   front-back confusion rates. This is the step that answers the question.
5. **Adopt if it won.** Same as adopting any other dataset — see below.

`pkgs/positional-audio-bench/src/positional_audio_bench/data/` vendors the
HUTUBS anthropometry (CC BY 4.0, TU Berlin — see `HUTUBS_SOURCE.md` there
for the citation) directly in the Python package; no fetch needed to run
`match-subject`. HUTUBS was picked over CIPIC for this because it has a
larger pool (96 subjects vs. CIPIC's 37 with usable pinna data) and a
cleaner, unit-unambiguous CSV.

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

Each `--dataset LABEL=PATH` is a label and a path to a SOFA file.

`pkgs/positional-audio-bench/datasets.nix` packages two CIPIC (UC Davis)
subjects — the only one of CIPIC/SADIE II/ARI/HUTUBS with an unambiguous
redistribution grant covering a public binary cache. Subjects 021 and 165 are
documented KEMAR mannequin variants with small and large pinnae
respectively, the closest thing to a size-matched dummy head without
measuring your own:

```sh
nix build .#positional-audio-bench  # or reference pkgs.positional-audio-bench-datasets in a config
```

`pkgs.positional-audio-bench-datasets.cipic-021-small-pinna` and
`.cipic-165-large-pinna` are the store paths.

**Measured result (2026-09-14, against ali-desktop's real config, both with
and without `compensationEq` applied — the EQ made no measurable difference
either way):**

| Dataset | Mean ITD err | Max ITD err | Front-back |
|---|---|---|---|
| KEMAR normal pinna (current default) | 3.0° | 15.0° | 8.6 dB |
| CIPIC 021, small pinna | 4.3° | 37.6° | 6.2 dB |
| CIPIC 165, large pinna | 4.1° | 22.1° | 7.2 dB |

**KEMAR won on every axis.** Neither CIPIC mannequin beat it, including on
front-back. This comparison is a fair use of the benchmark — both are
generic mannequins, neither is tuned to any specific listener, so "which
one has objectively stronger/more distinct measured cues" is a meaningful
question here (unlike comparing a *personalized* candidate this way — see
above). Matching pinna *size* alone doesn't help; CIPIC's older (2001)
measurement setup, on a different rig than KEMAR's, may also just be lower
fidelity, or the two datasets aren't directly comparable for reasons this
benchmark can't see. Either way: **swapping among these two available
generic dummy-head datasets didn't help.** That's weaker evidence than
"generic HRTFs have hit a ceiling" — it only rules out these two — but it's
consistent with the idea that the next real lever is a personalized match,
not another mannequin. See "Personalization" below.

If you still want to try a dataset this doesn't package (SADIE II, ARI,
HUTUBS, or a specific CIPIC subject — the license terms above are notes
specific to CIPIC, check any other source's license before packaging it),
get the SOFA file yourself and point `--dataset` at it directly; no need to
add it to `datasets.nix` for an ad-hoc comparison.

To adopt a winner: point
`modules.desktop.pipewire.binauralSurround.hrirFile` at the new SOFA file's
Nix store path, then re-measure `compensationEq` for it — a different HRIR
has different coloration, so the old EQ curve does not carry over.

## Adding a dataset to the Nix store properly

If a dataset's license allows redistribution and you want it available on
every machine (not just wherever you happened to download it), add a
`fetchurl`/`fetchzip` derivation in a new
`pkgs/positional-audio-bench/datasets.nix`, following the pattern other
fetched packages in this repo use (see `pkgs/lucien/default.nix` or
`pkgs/cavemem/default.nix` for `fetchFromGitHub`/`fetchurl` shape). Confirm
the license permits it first — some of these datasets are research-use-only.

## Known gaps

- Only CIPIC 021/165 packaged as ready-to-use `datasets.nix` derivations;
  HUTUBS anthropometry is vendored (for `match-subject`) but its SOFA files
  are fetched ad hoc per-match, not pre-packaged, since which subject you
  want depends on your own measurements.
- `biquad.py`'s RBJ formulas were diffed against PipeWire's actual SPA
  `spa/plugins/audioconvert/biquad.c` source (2026-09-14) and matched
  exactly — see `PENDING.md` for the detail.
- `live-verify` has not been run against real hardware yet.
- `perceptual-test` has not been run end-to-end against real hardware
  either — written against the same `pw-cat --playback` pattern
  `live.py` uses, but untested on an actual PipeWire session.
- No statistical guidance on how many `perceptual-test` trials are enough
  to trust a front-back confusion rate difference between two candidates
  as real rather than noise — 20 trials is a starting guess, not a derived
  number.

See `PENDING.md` for the same list with more detail.
