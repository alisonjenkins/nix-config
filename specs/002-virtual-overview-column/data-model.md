# Data Model: Virtual Output Overview Column

Runtime state only; nothing persists. Outputs are referred to by name, never by a held smithay
`Output`, because a virtual output gets a fresh `Output` each time it is turned off (ADR 0018).

## Monitor overview hooks (layout, set by `Niri`)

| Field | Type | Meaning | Rules |
|---|---|---|---|
| `overview_right_inset` | `f64` (logical px) | Width reserved at the right edge while the overview is open | ≥ 0 and finite, else treated as 0 and logged; effective width = inset × overview progress; 0 = upstream behaviour |
| `overview_offscreen_reachable` | `bool` | Overview rendering and hit-testing do not cull workspaces outside the output | Set only for virtual outputs that are tile sources; false = upstream behaviour |

## Band (per physical viewer)

| Field | Type | Meaning |
|---|---|---|
| `viewer` | output name | Physical output the band is on |
| `rect` | logical rect on viewer | Right edge, width `BAND_FRACTION (0.15) × viewer width × overview progress`, full height |
| `scroll` | `f64` | Column scroll offset in logical px, clamped to `[0, max(0, content_h − rect.h)]`; NaN → 0 |
| `content_h` | `f64` | Total height of labels, tiles and gaps |

Exists only while the overview is open (progress > 0), the session is unlocked, and at least one
virtual output is on. Scroll is kept per viewer across rebuilds while the overview stays open,
and reset on opening (FR-008).

## Group

| Field | Type | Meaning |
|---|---|---|
| `source` | output name | Virtual output |
| `label_rect` | logical rect on viewer | Name label row |
| `tiles` | `Vec<Tile>` | All workspaces of the source, in order, including the empty last one |

Order = virtual outputs in configuration order. A source with a zero or non-finite size is
skipped and logged at debug (FR-028).

## Tile (a `Projection` of kind `Tile`)

| Field | Type | Meaning |
|---|---|---|
| `viewer` / `source` | output names | As `Projection` |
| `workspace` | `WorkspaceId` | Workspace shown |
| `source_rect` | logical rect on source | That workspace's rect in the source monitor's own overview geometry |
| `region` | logical rect on viewer | Tile rect: width = band width − 2 × margin; height = width × source aspect |
| `active` | `bool` | Workspace is the source's active workspace (draws the highlight) |

`to_source` / `to_viewer` / `scale` come from `Projection` unchanged. Only tiles whose `region`
intersects the band's visible rect are projections that exist for input and rendering (culling).

## ProjectionKind

`Overview` (one per virtual output) is replaced by `Tile { workspace: WorkspaceId }`. `View`
(whole-source letterbox for view mode) is unchanged.

## ProjectionState

| Field | Change |
|---|---|
| `projections` | Now tiles plus at most one view projection per viewer |
| `viewing` | Unchanged (`Viewing { viewer, source, origin }`) |
| `bands` | New: `Vec<Band>` with groups, rebuilt with the projections |

Still rebuilt from scratch, never patched: on overview progress change, output on/off, workspace
add/remove/activate on a source, lock/unlock, view start/stop, and scroll change.

## OutputUnder

Adds `band: bool`: the position is inside a band but on no tile, so input is consumed and
nothing reacts (FR-015).

## Event-stream state (niri-ipc)

| Part | Field | Replicates as |
|---|---|---|
| `ViewOutputEventState` | `state: ViewOutputState` (`NotViewing` initially) | one `ViewOutputChanged` |
| `OutputsState` | `outputs: HashMap<String, Output>` | one `OutputsChanged` |

State transitions for view mode: `NotViewing → Viewing{viewer, source}` (start),
`Viewing → Viewing{…}` (source or viewer switched), `Viewing → NotViewing` (any stop). The event
reports `Viewing` or `NotViewing`; the `Stopped` response variant of the `view-output` request is
not used in events.
