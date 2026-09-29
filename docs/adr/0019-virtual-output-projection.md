# 0019. Show virtual outputs on physical monitors through projections

- Status: Accepted, pending live test
- Date: 2026-09-29

## Context

The patched niri on ali-desktop can create virtual outputs: monitors with no screen behind
them. `steam` exists for Steam Remote Play, but they are generic and more can be added.

A window that opens on a virtual output is invisible at the desk. On 2026-09-28 a KDE
Wallet unlock prompt opened on `steam` unseen, and every `gh` call hung behind it.

niri's overview is per monitor: each output draws only its own workspaces. A virtual
output's overview is drawn where nobody can see it.

## Decision

A **projection** maps a rectangle of a virtual output (the source) onto a region of a
physical monitor (the viewer) with one uniform scale. Only virtual outputs can be sources
and only physical outputs can be viewers, so projections never recurse. The design and its
spec live in `specs/001-virtual-output-projection/`; the code is in the niri fork
(`alisonjenkins/niri`, `rebase-feat-virtual`), shipped as `patches/niri-virtual-outputs.patch`.

- **Overview columns.** With the overview open, each enabled virtual output gets a column
  to the right of the viewer's own workspaces, labelled with its name. The column is the
  output's real overview, so dragging windows between any workspaces, dropping into gaps to
  create workspaces, reordering and clicking all work across outputs. The viewer's own
  workspaces stay exactly where niri draws them; columns shrink when they don't fit.
- **View mode.** `niri msg view-output <name>` (also a bind action, `Mod+Ctrl+V` here)
  shows one virtual output letterboxed on the focused physical monitor. Input goes to the
  virtual output, which becomes the active monitor, and a 2 s label says
  "Viewing: <name>". Overlay-layer surfaces such as notifications stay on top. It ends with
  `view-output` and no name (`Mod+Ctrl+Shift+V`), by clicking the viewer's own workspace in
  the overview, or automatically when either output goes away.
- **Rendering** wraps the source's own render elements in one `ProjectedElement` that maps
  geometry, damage and opaque regions from the source's scale to the viewer's. The source's
  own rendering, frame pacing and any stream from it are untouched.
- **Input** resolves through one projection-aware `Niri::output_under`. A guard test fails
  if new code calls `global_space.output_under` directly. The real cursor stays on the
  viewer; for projected hits the pointer focus location is synthesised as
  `pointer − surface_local`, so clients get exact surface-local coordinates at any scale.
- **State** (`ProjectionState`) is rebuilt, never patched, on overview changes, view
  start/stop, lock/unlock and output changes, and refers to outputs by name because a
  virtual output gets a fresh smithay `Output` every time it is turned off (ADR 0018).

## Lessons from implementation

- Stacking smithay's `Relocate` and `Rescale` elements passes the *viewer's* scale down to
  the source's elements, so sizes and positions disagree whenever the two scales differ. A
  dedicated `ProjectedElement` asks the inner element for geometry at the source's scale.
- Resolving pointer positions into sources must stop while the session is locked, or a
  click in a column's area reaches the source's lock surface. No projections exist while
  locked; view mode resumes after unlock.
- Hot corners must be checked on the output the pointer is physically on. Resolving them
  through a projection killed the viewer's own hot corner (it sits in a letterbox bar) and
  made the source's fire from inside the region.
- A virtual output must draw the pointer only while the pointer is physically over it. Never
  drawing it would drop a streaming client's own cursor from the stream; always drawing it
  leaks the desk cursor into the stream.
- Every code path that turns an output into a cursor position must use the *physical*
  output. Two independent reviews found nine places (warp-to-focus, pointer-lock hints,
  gesture wrap and clamp, grab deltas, confine regions) where a projected hit made the
  source the reference and teleported the cursor onto the virtual output. They are pinned
  by tests that drive real input through a test input backend (`src/tests/input.rs`).
- The patch base must be the niri revision the flake builds. It had drifted 49 commits
  behind; old hunks applied with fuzz until new ones didn't. Renderer tests are named
  `egl_` because the Nix build skips `::egl` (no EGL display in the sandbox).

## Alternatives rejected

- **Render the virtual output's windows natively at the viewer's scale.** Needs windows on
  two outputs at once, fighting niri's one-output-per-window model.
- **A mirror client** (screencast in a fullscreen window plus focus-monitor bindings).
  Cannot pass mouse clicks through, cannot join the overview, no drag and drop.
- **A thumbnail strip in the overview.** Shows, but cannot be used like the overview.
- **Esc to leave view mode.** Esc belongs to the focused application; the rule would be
  unpredictable.
- **Centre the whole overview row.** Moves the viewer's own workspaces and needs `Monitor`
  geometry changes in both rendering and hit-testing.
- **Patch Qt, or GTK.** The crashes that started this (ADR 0018) were fixed at their source
  in niri instead.

## Consequences

- A stream from a virtual output does not show the desk user's cursor.
- A remote client and the desk user moving the pointer at once contend for it; accepted.
- Projected content is scaled, so it can look softer than native.
- Drag deltas inside a shrunk column are scaled slightly wrong because niri divides by the
  viewer's overview zoom; drop targets use the absolute position and stay correct.
- In view mode, Alt-Tab opens on the viewer, and its input resolves on the physical output
  only. While it is open, input over an overview column closes it instead of reaching it.
- A window screenshot's cursor position stays in the source's coordinates.

## Revisit when

- The virtual-output patch is upstreamed to niri: projections go with it, as their own PR.
- niri gains native multi-output overview rendering, which would replace the columns.
- The live check (quickstart manual steps) shows frame drops below the viewer's refresh
  rate with the overview open during a stream.
