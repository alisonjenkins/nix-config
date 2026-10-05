# Quickstart: prove each phase of foveated rendering for VR games

Run these on ali-desktop in order. Each section says what must be true before it and what you
should see. Commands that launch a game need you to start it or approve it. Commands that need
root are listed for you to run; none is run for you.

## Phase 0: spikes

### S1: layered rate image on the target GPU

Prerequisite: the probe in `research/vrs-probe/`.

```bash
specs/005-vr-foveated-rendering-injector/research/vrs-probe/run.sh
```

Expect: the summary lists Q1 to Q6 as PASS. After the spike adds a layered, non-multiview case,
the new line states PASS or FAIL for a one-layer rate image on a two-layer target. A FAIL means
layered passes use per-draw rates (see `plan.md`).

### S2: what Fallout 4 VR renders

Prerequisite: Fallout 4 VR installed (already done) and started once from Steam.

Expect: the game's Proton log names Direct3D 11, and DXVK's log lists the large colour
targets with size, layers, format and samples. Record them in `research.md`.

### S3: compat tool layering

Expect: a game launched with the layered compat tool prints a DXVK version line from the
replaced build, and the runner updater leaves the tool alone after its next run.

### S4: headless VR

Prerequisite: null driver settings in `~/.local/share/Steam/config/steamvr.vrsettings`
(managed by the existing home module).

Expect: Fallout 4 VR keeps producing frames for 60 s with no headset. If it does not, use the
Quest over Steam Link with a fixed pose and note that stream-encoder load is excluded.

### S5: DXVK base

Expect: the fork builds unmodified through Nix and its version line matches the base chosen for
the user's runner.

## Phase 1: measurement harness (Story 1)

```bash
nix build .#vr-foveation-bench
nix flake check   # or: just check
```

Expect: the statistics tests pass. Then take 5 interleaved runs per condition, each logging the
whole session from game start with the sampler running alongside. The report trims every run to
the same measured window, so warm-up never counts:

```bash
vr-foveation-bench report --meta meta.json --off off1.csv ... --on on1.csv ... \
  --off-power off1-sampler.csv ... --on-power on1-sampler.csv ... \
  --skip-seconds 60 --window-seconds 60 --artefacts unknown --out report.json
```

It prints per-run medians, p99, mean power, noise and the verdict, and exits 0. It refuses to
overwrite an existing `report.json` unless `--force` is given.

Take two baselines: stock Proton, and the patched tool with `DXVK_FOVEATION` unset. Expect the
second to match the first within noise (SC-005).

Optional, needs your approval: pinning GPU clocks lowers noise but raises power. To do it
yourself, run `echo profile_peak | sudo tee /sys/class/drm/card1/device/power_dpm_force_performance_level`
before the runs and write `auto` back after. The card index may differ; confirm device
`0x7550` first.

## Phase 2: foveation and fallbacks (Stories 2 and 3)

1. In Steam, pick the foveated compat tool for Fallout 4 VR and set the launch option
   `DXVK_FOVEATION=1 %command%`.
2. Run the 60 s scene with the option off, then on, interleaved five times.

Expect: with the option on, the log shows `event=profile_loaded` and `event=pass_matched`, and
the report shows the measured difference with its noise. With the option removed, the game
behaves as before and no foveation line appears.

Forced failures (each must start the game normally and log a reason): remove the profile,
set a size that matches nothing, set the sample count to 8, and run on a GPU or driver not on
the verified list. Expect `reason=no_profile`, `no_pass_matched`, `samples_unsupported` and
`unverified_gpu` respectively.

## Phase 3: profiles and verdicts (Story 4)

Expect: `DXVK_FOVEATION_DISCOVER=1` lists candidate targets; editing the profile's inner radius
in a scratch file and launching once with `DXVK_CONFIG_FILE` pointing at it changes the
full-quality region with no system switch; `docs/vr-foveation/verdicts.md` has a row for
Fallout 4 VR.

## Phase 4: gaze interface (Story 6, interface only)

Expect: the synthetic source moves the region along a known path, the region follows within
one frame of each update, and it returns to the fixed centre after the timeout without a
visible jump.
