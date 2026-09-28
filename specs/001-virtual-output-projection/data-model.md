# Data Model: Virtual Output Projection

All types live in the niri fork. Geometry is in logical coordinates unless stated.

## Projection (`src/projection.rs`, pure)

| Field | Type | Meaning |
|---|---|---|
| `viewer` | `String` (output name) | Physical output that shows the source. |
| `source` | `String` (output name) | Virtual output being shown. |
| `source_rect` | `Rectangle<f64, Logical>` | Area of the source that is shown: its whole output in View mode, or its overview workspace strip in Overview. Source-local. |
| `region` | `Rectangle<f64, Logical>` | Where that area appears on the viewer. Viewer-local. Same aspect ratio as `source_rect`. |
| `kind` | `ProjectionKind` | `Overview` or `View`. |

Derived:
- `scale() = region.size.w / source_rect.size.w`, which is uniform because the aspect ratio is kept.
- `to_source(p) -> Option<Point>`: `None` if `p ∉ region`. Otherwise
  `source_rect.loc + (p - region.loc) / scale()`.
- `to_viewer(p) = region.loc + (p - source_rect.loc) * scale()`.

Invariants (checked in the constructor, which returns `Result`):
- `source_rect` and `region` are non-empty, and their aspect ratios match within 1e-6.
- `viewer != source`.

Names are stored rather than `Output` handles, because a virtual output gets a fresh smithay
`Output` every time it is turned off. Handles are looked up by name when rendering and
hit-testing.

## ProjectionState (field of `Niri`)

| Field | Type | Meaning |
|---|---|---|
| `projections` | `Vec<Projection>` | Current projections. Rebuilt, never patched. |
| `viewing` | `Option<Viewing>` | Present while a viewer is in view mode. |

`Viewing { viewer: String, source: String }` records what the user asked for. `rebuild()`
turns it into a `View` projection, or drops it if the viewer or source is gone (FR-015).

### When it is rebuilt

- The overview opens or closes, and each overview-progress change while it animates.
  Columns move with the zoom.
- `view-output` starts or stops view mode.
- An output is added, removed, turned on or off, resized or changes scale.

### State transitions (`viewing`)

```
None ──view-output <name> (valid)──▶ Some(viewer, name)
Some ──view-output (no name)──────▶ None
Some ──source off/removed─────────▶ None  (+ notice, viewer becomes active)
Some ──viewer removed─────────────▶ None
Some ──view-output <other>────────▶ Some(viewer, other)
None ──view-output (no name)──────▶ None  (reply: not viewing)
```

## Output classification (`src/backend/virtual_output.rs`)

- `is_virtual_output(&Output) -> bool` is true when the output's `OutputName` has
  `make == Some("niri")` and `model == Some("virtual")`.
- **Sources** are enabled outputs, in the layout, for which `is_virtual_output` is true.
- **Viewers** are outputs for which `is_virtual_output` is false.

## overview_columns (`src/projection.rs`, pure)

The input is the viewer's own overview strip (`Rectangle`), the viewer size, and for each source
its `source_rect` size.

The output is one `region` per source, placed in this order:
1. Scale is 1 for every source.
2. Place the regions left to right after the viewer's strip, separated by a gap of
   `0.05 × viewer height`.
3. Centre the whole row (the viewer strip plus the regions) horizontally on the viewer.
4. If the row is wider than 95% of the viewer, scale all source regions down uniformly until it
   fits. The viewer strip is never scaled.
5. Centre each region vertically.

## ViewOutputError (extends `VirtualOutputError`)

| Variant | When |
|---|---|
| `NotFound(name)` | No output has that name (existing variant). |
| `NotVirtual(name)` | The output is physical. |
| `Disabled(name)` | The virtual output is off. |
| `NoViewer` | There is no physical output to show it on. |

The messages name the output: "output 'DP-2' is not a virtual output".
