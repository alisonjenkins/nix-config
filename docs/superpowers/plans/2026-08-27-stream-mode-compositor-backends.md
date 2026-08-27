# stream-mode: compositor backends beyond niri

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `stream-mode` drive Steam Remote Play at the client's resolution on
window managers other than niri, without changing its behaviour on niri.

**Not a goal:** supporting every desktop. Some cannot host this at all (see
§"Where this cannot work"). Saying so precisely is part of the deliverable.

**Status:** not started. Written 2026-08-27 while the niri implementation was
still being verified. **Do not start this until the niri path is merged and
confirmed working** — a second backend written against an unfinished first one
abstracts the wrong things.

**Architecture:** `stream_mode.py` already separates its Steam-facing half from
its compositor-facing half, and `Session` already speaks in compositor-neutral
verbs rather than issuing `niri msg` itself. The work is to make that implicit
seam explicit, normalise the one data shape that leaks across it, and add
backends behind it.

**Read first:** `docs/steam-remote-play-streaming.md` for how the components
relate, and `PENDING.md` for the traps.

## Where the system stands today

Three parts, with very different portability:

| Part | Portable today? |
|---|---|
| `pkgs/steam-display-filter` | **Yes, completely.** No compositor code. `STEAM_STREAM_SIZE=1280x800` works on anything. Nothing in this plan touches it. |
| `stream_mode.py`, Steam-log half | **Yes.** Log parsing, client learning, `clients.json`, `publish_target`. No compositor concepts. |
| `stream_mode.py`, compositor half | **No.** 66 `niri` references. |

Measured coupling, so the estimate is not a guess:

| Leak | Location | Kind |
|---|---|---|
| `# --- niri ---` section | lines 190–580 | Contained; replaceable wholesale |
| `handle_niri_event` parses niri's event JSON | line 1442+ | Contained |
| `live_niri_socket` — `niri.<display>.<pid>.sock` | lines 193–238 | Contained |
| `Session` reads niri's **window schema** directly (`layout.window_size`, `workspace_id`, `is_focused`, `app_id`, `title`) | ~15 sites in 611–1234 | **Leaked into the logic** |
| `widen_column_to_output` — niri scrolling-layout vocabulary | line 458 | **A concept, not just a name** |

The favourable finding: **`Session` never calls `niri msg` directly.** It calls
named verbs. That is a backend interface in all but name, and it is why this is
a day of work rather than a rewrite.

The unfavourable finding: `widen_column_to_output` exists *because* niri cannot
set fullscreen — it only toggles, and exposes no state to read first
(niri-wm/niri#2836, #338). Every other candidate compositor has set-semantics
fullscreen and would implement `fill_output` correctly and in one line. **niri
is the awkward backend, not the reference one.** Do not let its shape dictate
the interface.

## The interface

Ten operations and one event stream. This is the whole porting surface.

```python
class Backend(Protocol):
    def outputs(self) -> dict[str, tuple[int, int]]: ...
    def set_output_mode(self, name, w, h, hz) -> bool: ...
    def set_output_enabled(self, name, enabled: bool) -> bool: ...
    def windows(self) -> list[Window]: ...
    def workspaces(self) -> list[Workspace]: ...
    def move_workspace_to_output(self, name, output) -> bool: ...
    def move_window_to_output(self, window_id, output) -> bool: ...
    def fill_output(self, window_id) -> bool: ...
    def focus_window(self, window_id) -> bool: ...
    def events(self) -> Iterator[Event]: ...
```

```python
@dataclass(frozen=True)
class Window:
    id: int | str
    app_id: str          # app_id (wlroots) / class (Hyprland) / wm_class (X11)
    title: str
    pid: int | None
    size: tuple[int, int] | None
    workspace_id: int | str | None
    focused: bool
```

Events normalise to five kinds, which is what the niri handler already reacts
to: `WindowsReplaced`, `WindowChanged`, `WindowResized`, `WindowClosed`,
`WorkspacesChanged`.

Notes on two operations that are less obvious than they look:

- **`fill_output` is "make this window cover the output"**, not "fullscreen it"
  and not "maximise it". niri implements it as `set-column-width 100%` because
  that is the only idempotent option available there; everyone else implements
  it as set-semantics fullscreen, which is strictly better — the window is
  actually told it is fullscreen, and it works with non-zero gaps.
- **`set_output_enabled` presumes a declared output that is toggled**, not one
  created per stream. That design came from niri (creating per stream raced its
  own output handling) but it is likely right everywhere. Where a backend can
  only create and destroy, it may implement enable/disable as create/destroy —
  but must preserve the teardown *ordering* contract below.

## Contracts every backend must honour

These are not implementation details. Violating either reintroduces a bug that
took a long time to find the first time.

1. **Teardown order: disable the output, then withdraw the target.** Reversed,
   Steam recomputes while the output is still present and the filter is already
   inert, caches the union of both monitors, and sizes the *next* stream to it.
2. **The output must be non-primary.** Steam's capture geometry is the bounding
   box of every monitor except the primary. "Make the streaming display primary"
   is the usual advice and is backwards.

Both belong in the backend test suite, not just in prose.

## Compositor survey

**Everything in this table is UNVERIFIED and must be confirmed by Task 1 before
any of it is designed against.** It is written down as the current best
understanding and its confidence, not as findings.

| Compositor | Create/enable a virtual output | Event stream | Set-semantics fullscreen | Move workspace to output | Confidence |
|---|---|---|---|---|---|
| niri (patched) | yes — `virtual-output` in config | `niri msg event-stream` | **no — toggle only** | yes | Verified; this is the shipping backend |
| sway | `swaymsg create_output` (headless backend) | IPC `subscribe` | `fullscreen enable` | yes | Medium — the wayvnc workflow relies on the headless-output half |
| Hyprland | `hyprctl output create headless` | socket2 | `dispatch fullscreen` | `moveworkspacetomonitor` | Medium |
| Wayfire | virtual-output plugin? | ? | ? | ? | Low — do not assume |
| GNOME / Mutter | internal virtual monitors exist for remote desktop; no known addressable scripting IPC | no | no | no | Low, leaning **not supported** |
| KDE / KWin | as above | no | no | no | Low, leaning **not supported** |
| X11 WMs | `xrandr --setmonitor` / dummy driver; wmctrl for windows | no | varies | varies | Low — a genuinely different design |

## Where this cannot work

Worth stating plainly in the module's documentation once Task 1 settles it, so
nobody re-derives it:

- A compositor with **no scriptable way to add an output** cannot host this at
  all. The filter alone still helps if the user can arrange a suitably-sized
  output some other way, but the watcher has nothing to drive.
- A compositor with **no event stream** could be polled, but the niri
  implementation was polled first and it raced asynchronous creation badly
  enough to be rewritten. A polling backend should be considered a downgrade
  and gated behind an explicit opt-in.
- Without **workspace-to-output movement**, `borrow_game_workspace` has no
  equivalent. `move_window_to_output` per window already exists as a fallback
  and would have to carry the whole job — meaning games that launch *after* the
  stream starts need catching individually rather than inheriting placement.

---

### Task 1: Establish the capability matrix

Nothing else in this plan is safe to design until the survey above is fact.
Every row is currently a guess.

- [ ] For sway, Hyprland and Wayfire, confirm from **current upstream
      documentation and source** — not blog posts — whether each can (a) create
      or enable an output with no monitor behind it, (b) emit window and
      workspace events on a subscribable channel, (c) set fullscreen with set
      rather than toggle semantics, (d) move a named workspace to an output.
- [ ] For GNOME and KDE, establish whether any supported IPC can add an output.
      A negative here is a real finding — record where it was checked so the
      next person does not repeat it.
- [ ] Check whether the virtual output reports a **non-zero physical size** on
      each. Steam discards `0mm x 0mm` outputs; niri needed patching for exactly
      this, and any backend with the same defect needs the same fix or the
      filter's fallback.
- [ ] Rewrite the survey table above with the findings and the evidence, and
      replace the confidence column with a link to what was checked.

**Verification:** the table contains no "?" and no "Low" confidence rows.

**This task may conclude the plan.** If only niri and one other compositor turn
out to be viable, the abstraction may not be worth its cost — say so and stop.

---

### Task 2: Normalise the window record

Mechanical, valuable on its own merits, and safe to do **before** Task 1
resolves. This is the leak that would otherwise force a second pass.

- [ ] Add the `Window` dataclass above.
- [ ] Convert `niri_windows()` to return `list[Window]`.
- [ ] Replace the ~15 sites in `Session` that destructure niri dicts
      (`(w.get("layout") or {}).get("window_size")`, `w.get("workspace_id")`,
      `w.get("is_focused")`, `w.get("app_id")`, `w.get("title")`) with attribute
      access.
- [ ] Update `trace()`, which takes a raw `layout` dict today.

**Verification:** the 117 existing tests pass unchanged in behaviour. Fixtures
will need rewriting to construct `Window` — that is the point; they currently
encode niri's JSON shape.

---

### Task 3: Rename `widen_column_to_output` to `fill_output`

- [ ] Rename, keeping the niri-specific `set-column-width "100%"` inside it.
- [ ] Move the explanation of *why* it is a column width — and the
      `warn_if_short_of_output` caveat — into that function, where a backend
      author will read it.
- [ ] Update `WIDEN_LIMIT` and the log strings to match.

**Verification:** tests pass; `grep -c column stream_mode.py` finds matches only
inside the niri backend.

---

### Task 4: Extract the `Backend` protocol

- [ ] Define `Backend` and the normalised `Event` kinds.
- [ ] Move lines 190–580 and `handle_niri_event` into a `NiriBackend` class.
- [ ] Give `Session` a backend at construction and replace module-level verb
      calls with `self.backend.<verb>`.
- [ ] Keep `live_niri_socket` inside `NiriBackend` — it is niri's problem.

**Verification:** no behaviour change. Tests pass. `grep -c niri` outside the
niri backend returns 0 (comments aside).

---

### Task 5: A fake backend, and the contract suite

- [ ] Add `FakeBackend` recording calls and replaying scripted events.
- [ ] Re-point the existing tests at it, replacing subprocess mocking.
- [ ] Add a **contract suite** any backend must pass, asserting the two
      contracts above: teardown disables before withdrawing, and the streamed
      output is never made primary.

**Verification:** the suite fails against a deliberately mis-ordered fake.

---

### Task 6: Backend selection

- [ ] Select from `$STREAM_MODE_BACKEND`, else infer from
      `$XDG_CURRENT_DESKTOP` / `$NIRI_SOCKET` / `$SWAYSOCK` / `$HYPRLAND_INSTANCE_SIGNATURE`.
- [ ] On an unsupported compositor, exit with a message naming what was
      detected and what is supported — not a traceback.
- [ ] Make the home-manager module's `niriPackage` option backend-shaped rather
      than niri-shaped, keeping the existing name working.

**Verification:** a fabricated environment selects each backend; an unknown one
exits with the intended message.

---

### Task 7: A second real backend

Only if Task 1 says it is viable. Whichever of sway/Hyprland scored best.

- [ ] Implement against the contract suite.
- [ ] Implement `fill_output` as **set-semantics fullscreen**, not as a width.
- [ ] Verify on real hardware against a real client — the false-pass traps in
      `PENDING.md` apply in full, especially "two outputs must be present".
- [ ] Record the result in `docs/steam-remote-play-streaming.md`.

**Verification:** an actual stream at the client's resolution, quoting
`SynchronizeClientState(): setting capture size` from the Steam log.

---

## Sizing

Tasks 2–6 are about a day, no behaviour change, all verifiable by the existing
suite. Task 1 gates Task 7 and may cancel it. Tasks 2 and 3 are worth doing
regardless of whether the rest ever happens: they remove a real leak and fix a
misleading name.
