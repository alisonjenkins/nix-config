# Interfaces: Foveated rendering for VR games that lack it

The feature has no network service. Its external surfaces are environment variables, a
configuration file, a gaze sample format, log lines and a report file. These are the contracts
tests and users rely on.

## 1. Environment variables

| Variable | Set by | Meaning |
|----------|--------|---------|
| `DXVK_FOVEATION` | Steam launch option | Opt-in. Set to `1` to apply foveation using the game's profile. Unset or `0`: the patched DXVK behaves like stock and does not enable the shading-rate extension. |
| `DXVK_FOVEATION_DISCOVER` | Steam launch option | `1` logs candidate eye-image targets; applies nothing. |
| `DXVK_FOVEATION_MEASURE` | Measurement wrapper | `1` writes per-frame GPU timestamps to the measurement log. Independent of the above. |
| `DXVK_FOVEATION_OVERRIDE_GPU` | Owner | `1` allows foveation on a GPU and driver not yet verified (FR-017). |
| `DXVK_CONFIG_FILE` | Home module, or the owner | Path to the DXVK config containing the profiles. The home module sets the default; the owner can point one launch at a scratch file to tune a profile without a system switch. |

## 2. Profile keys (in the DXVK config file, per executable)

Keys use the `dxvk.foveation.` prefix. An unknown key or a value out of range disables
foveation for that game and logs the key. Each game is a `[Fallout4VR.exe]` section (exact,
case-sensitive Windows executable name), and a value with spaces must be quoted.

`dxvk.foveation.enabled` (true or false, default false) allows foveation for the game. It does
not turn it on: that still needs `DXVK_FOVEATION=1` in the launch options (section 1). The home
module writes it for every game, so a profile can be kept in the file and switched off.

```text
[Fallout4VR.exe]
dxvk.foveation.enabled = true
dxvk.foveation.match.minWidth = 1000
dxvk.foveation.match.minHeight = 1000
dxvk.foveation.match.layers = 1
dxvk.foveation.match.format = R8G8B8A8_SRGB
dxvk.foveation.match.samples = 4
dxvk.foveation.region.bands = 0.45:1x1,1.0:2x2
dxvk.foveation.gaze.source = fixed
```

`region.bands` is a comma-separated list of `radius:rate` pairs, radii strictly increasing in
(0, 1] as a fraction of the half-width. The first band is the full-quality centre and must be
`1x1`; each later band runs from the previous radius out to its own. There is no separate
inner-radius key, so the centre is defined in one place.

## 3. Gaze sample (shared memory, later phases)

Layout matches the pattern of the existing community reader: a magic value, a sequence counter
read before and after the payload so a torn read is detected and retried.

```text
u32 magic      'GAZE'
u32 sequence   odd while being written
u32 valid      0 or 1
f32 cx[2]      per-view centre, 0..1 across the target, view 0 = left, view 1 = right
f32 cy[2]      per-view centre, 0..1 down the target
u64 timestamp_ns   monotonic clock of the writer
```

Rules: a sample older than the profile timeout (default 100 ms) or with `valid = 0` returns
the region to the fixed centre. With one shared rate image per target, the layered case uses
the mean of the two centres.

Source interface: `read() -> {valid, cx[2], cy[2], age_ms}`. The fixed and synthetic sources
exist now. An OSC or shared-memory source is added when a Steam Frame is in hand.

## 4. Log lines

One line per decision, `key=value` pairs, ISO 8601 UTC timestamp first, prefix `dxvk-foveation`.

```text
2026-10-05T10:00:00Z dxvk-foveation event=profile_loaded exe=Fallout4VR.exe
2026-10-05T10:00:01Z dxvk-foveation event=pass_matched width=2016 height=2240 layers=1 format=R8G8B8A8_SRGB samples=4
2026-10-05T10:00:01Z dxvk-foveation event=disabled reason=unverified_gpu gpu="..." driver="..."
2026-10-05T10:00:01Z dxvk-foveation event=fallback reason=no_pass_matched profile_field=match.width
```

`event` is one of `profile_loaded`, `pass_matched`, `pass_skipped`, `rates_applied`,
`disabled`, `fallback`, `discover_candidate`. `reason` values are stable strings that tests
assert on: `no_profile`, `invalid_profile`, `no_pass_matched`, `unverified_gpu`,
`extension_missing`, `samples_unsupported`, `game_sets_own_rates`.

## 5. Measurement log and report

The fork writes `frame,gpu_ms,eye_pass_ms,unix_s` rows (CSV, header included) to
`$XDG_STATE_HOME/dxvk-foveation/<exe>-<timestamp>.csv`. `unix_s` is the wall-clock time of the
frame in seconds since the Unix epoch. The sampler writes
`time_s,power_w,core_mhz,gpu_busy_percent,temp_c,unix_s` rows with the same wall clock, so the
two logs share one time axis even though they are started separately.

The Python package reads both and writes a report as JSON with the fields in `data-model.md`
(measurement report), including `headsetOrDisplay`, `build` and `eyePassShare`. Times are ISO
8601 UTC.

Window: `report` takes `--skip-seconds S` (default 0) and `--window-seconds W` (default: to the
end of the frame log). The window starts at the first frame's `unix_s` plus S. Frames and
sampler samples are both trimmed to it, so warm-up, loading screens and menus never enter the
medians or the mean power. The window used is stored in each run of the report. A run is a
bad-input error when it has no frames or fewer than two sampler samples inside the window, when
the frame log ends more than one second before a requested window end (the run stopped early),
or when the sampler starts or ends more than one second inside the window edges.

`report` refuses to overwrite an existing output file unless `--force` is given.

Exit status for the report tool: 0 when a report was written, 1 on bad input, 2 when the
runs are too few to compute noise (fewer than 3 per condition).
