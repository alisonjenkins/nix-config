# Data Model: Foveated rendering for VR games that lack it

Entities from the spec, with fields and rules. Field names here are the names used in the
configuration and report formats in [contracts/interfaces.md](contracts/interfaces.md).

## Game profile

One per game, keyed by executable name (and optionally Steam app ID for the report).

| Field | Meaning | Rule |
|-------|---------|------|
| `enabled` | Foveation on for this game | Default false. True only when the launch option also sets `DXVK_FOVEATION`. |
| `match.minWidth`, `match.minHeight` | Smallest target that counts as an eye image | Positive integers. |
| `match.width`, `match.height` | Exact target size, when known | Optional; overrides the minimums. |
| `match.layers` | Layer count of the target (1 or 2) | Optional. |
| `match.format` | Colour format of the target | Optional; named, not numeric. |
| `match.samples` | Sample count | 1, 2 or 4. A profile naming 8 is invalid, because 8x MSAA ignores rates. |
| `region.bands` | List of `(radius, rate)` outward from the centre; each radius is a fraction of the half-width in (0, 1] and each band runs from the previous radius to its own | The first band is the full-quality centre and must be 1x1, so the centre is defined in one place. Rates limited to what the GPU lists (2x2 on this GPU); radii strictly increase. |
| `gaze.source` | `fixed` or `synthetic` (later `osc`, `shm`) | Unknown values disable foveation and log it. |

Validation: an invalid profile disables foveation for that game and logs which field failed;
it never aborts the game.

## Eye-image pass

Not stored. Recognised at render pass begin from the target's size, layer count, colour format
and sample count against the profile's `match` fields. In discovery mode, every colour target
above a size floor is logged once per second with those four values and a hit count, so the
profile can be written.

## Foveation region and rate map

Derived from the profile, the target size and the gaze sample.

| Field | Meaning |
|-------|---------|
| Tile size | 8x8 pixels (read from the device, not assumed) |
| Map size | `ceil(width / 8)` by `ceil(height / 8)` tiles, one layer |
| Tile value | Rate code `(log2(w) << 2) OR log2(h)`, with `w` and `h` capped at the device's maximum rate |
| Centre | Gaze sample, or the target centre when fixed |

The map is shared by every layer of the target (one layer; layered rate images are
unsupported on this GPU).

## Gaze sample

See `contracts/interfaces.md`. Fields: sequence number, validity, per-view centre in
normalised target coordinates (0 to 1). A sample older than the timeout is treated as invalid
and the region returns to the fixed centre.

## Measurement report

One per run set (a condition measured several times).

| Field | Meaning |
|-------|---------|
| `game`, `appId`, `gameBuild` | What was measured |
| `driver`, `gpu`, `undervoltMv` | Environment, including the active undervolt |
| `headsetOrDisplay` | Headset and its render settings (resolution, refresh rate, supersampling), or the null-driver window settings used |
| `build` | `stock` for stock Proton, `patched-off` for the patched tool with the option unset, `patched-on` with it set |
| `condition` | `off` or `on`; the three `build` values above are compared in pairs |
| `eyePassShare` | Median eye-pass time divided by median GPU frame time |
| `runs[]` | Per run: frames, median and p99 GPU frame time (ms), median eye-pass time (ms), mean power (W), mean core clock (MHz), start and end temperature |
| `window` (per run) | `skipSeconds`, `windowSeconds`, `windowStartUnixS`, `windowEndUnixS`: the measured window that frames and power samples were trimmed to |
| `noise` | Spread of per-run medians within the condition |
| `date` | ISO 8601 UTC |

## Verdict

One row per game in `docs/vr-foveation/verdicts.md`.

| Field | Meaning |
|-------|---------|
| `game`, `date`, `driver` | Context |
| `verdict` | `go`, `no-go` or `inconclusive` |
| `gpuTimeChange`, `powerChange`, `noise` | Measured change with the noise next to it |
| `artefacts` | Notes and screenshot paths |

State rule: `go` when GPU time or power drops by more than twice the larger within-condition
noise, with the same sign in every interleaved pair, and the artefacts are tolerable;
`no-go` when neither drops beyond noise or the artefacts are not tolerable; `inconclusive`
when the runs were too noisy to tell.

"Too noisy to tell" is a spread of at least 5% of the off median in a compared metric when no
metric shows a beyond-noise change. A beyond-noise increase with no reduction is `no-go`.
Unjudged artefacts with a reduction give `inconclusive`, with the reason "artefacts not
judged".
