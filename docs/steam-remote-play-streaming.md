# Steam Remote Play at the client's resolution

How the host streams to a Steam Deck (or a TV, or a phone) at *that client's*
resolution, while a 5120x1440 ultrawide stays connected and usable.

This document is the map. Each component's own comments carry the detail; what
is written down here is the part no single file can tell you — how the five
pieces fit together, and which of the couplings between them are load-bearing.

## The problem

Two independent faults, which look like one symptom.

**Remote Play captures a whole output.** Its portal picker has no "Window" tab —
other clients' pickers on the same portal do — so no window-scoped source can
reach it. Stream an ultrawide to a 16:10 Deck and the game is letterboxed into a
fraction of the client's frame.

**Steam sizes the encoder from its own idea of the desktop, not from the
PipeWire stream the portal handed it.** So merely giving it a correctly-sized
output to capture is not enough: the capture is right, and Steam still encodes
at the wrong geometry. That idea of the desktop comes from **SDL3**, not from X
— `steamui.so` calls `SDL_GetDisplays(NULL)`, walks the NULL-terminated array
calling `SDL_GetDisplayBounds` on each, and unions them. With two outputs
present, the union is the ultrawide.

Fixing one without the other changes nothing visible, which is why this took
several wrong turns. See `PENDING.md` for the full archaeology.

## The pieces

| Component | Lives in | Does |
|---|---|---|
| niri virtual-output patch | `patches/niri-virtual-outputs.patch` | Gives the compositor an output that has no monitor behind it |
| Output declaration | `home/programs/linux-only/niri/module.nix` | Declares the `steam` output in niri's config, disabled |
| Watcher | `home/programs/linux-only/steam-stream-mode/` | Reacts to stream and compositor events; owns all state |
| SDL filter | `pkgs/steam-display-filter/` | Makes Steam see one display, sized to the stream |
| Host wiring | `flake-modules/hosts/ali-desktop/default.nix` | `LD_PRELOAD` + `STEAM_STREAM_TARGET` into Steam's environment |

### 1. niri virtual-output patch

A rebase of `QaidVoid/niri` `feat/virtual` onto `e9b215fe`, plus local fixes.
Adds a `virtual` output kind that can be declared in the config file like any
other output, so it takes part in normal `output` handling — enable, disable,
`mode`, workspace assignment — rather than being a special object created over
IPC.

Two local fixes on top, both worth keeping if this is ever upstreamed:

- **A real physical size.** Upstream reports `0mm x 0mm` for virtual outputs.
  Steam *discards* such outputs entirely, so the streamed output was never even
  a candidate. The patch derives millimetres from the mode at ~96dpi.
- **No crash on output reconnect**, which the original hit whenever DP-2 came
  back.

Gated behind `modules.desktop.niriVirtualOutputs`, **off by default**. When off,
the stock upstream niri is used and none of this is built.

The patch is *generated*, not hand-edited: `git diff e9b215fe HEAD` on the
fork's `rebase-feat-virtual` branch. Fixes belong there as commits — so they
keep their rationale and their tests — and the patch is regenerated afterwards.

### 2. Output declaration

`niri/module.nix` renders a `virtual-output` block per entry in
`custom.niri.virtualOutputs`:

```nix
custom.niri.virtualOutputs.steam = {
  width = 1280;
  height = 800;
  refresh = 90;   # the OLED Deck's panel; caps the client's rate
};
```

The watcher's defaults are read straight back out of this
(`home/machines/ali-desktop/default.nix`), so the declared output and the size
used for an unknown client cannot drift apart.

The output is declared **once, at config load, and left disabled**. It is not
created on demand.

> This is the second design. The first created and destroyed the output over
> IPC per stream, which raced with niri's own output handling and produced
> outputs that held their name but were unusable. Toggling a declared output is
> the same operation niri already performs when a monitor is plugged in, and it
> inherited that path's correctness for free.

### 3. The watcher — `stream-mode`

A single Python program, event-driven, no polling. It is the only component
holding state, and it is the only one that decides anything.

**Inputs** — two tailed logs and one event stream:

| Source | Watched for |
|---|---|
| `streaming_log.txt` | `>>> Starting/Stopped desktop stream`, `CLIENT: Video size: …, output size: WxH`, `Adding window … for process … and gameID …` |
| `connections_log.txt` | `Client N (name) connected via direct connection`, `Received streaming request N with device ID N` |
| `niri --json event-stream` | `WindowOpenedOrChanged`, `WindowLayoutsChanged`, `WorkspacesChanged`, `WindowClosed` |

The two client-identifying patterns exist because clients do not announce
themselves the same way. The Deck uses direct connection; an Android TV client
arrives as a streaming request with a device ID.

**Outputs** — `niri msg` actions, and one file.

**The sequence, on connect:**

1. Look up the client's learned size in
   `$XDG_STATE_HOME/stream-mode/clients.json`. Unknown client → the
   configured default (1280x800, the Deck's panel).
2. `set_output_mode` on the declared `steam` output, then `set_output_enabled`.
3. `publish_target` writes `WIDTHxHEIGHT` to the target file. **This is what
   arms the SDL filter** — until the file exists, the filter does nothing.
4. `borrow_game_workspace` moves the whole `game` workspace onto the streamed
   output with `move-workspace-to-monitor --reference`. Games are pinned to
   that workspace by a niri window rule, so moving the workspace moves every
   game, present and future, without per-window handling.
5. As windows appear, `fill_streamed_output` widens the game's column to
   `set-column-width "100%"`, and `refocus_streamed_window` focuses it.
   Both idempotent, both capped (`WIDEN_LIMIT`, `REFOCUS_LIMIT`) so a window
   that genuinely cannot be corrected does not loop forever.
6. `learn` records the client's real size from `CLIENT: Video size: …, output
   size: WxH` for next time.

**On teardown — the order matters:**

1. `set_output_enabled false`
2. *then* `withdraw_target`
3. `return_game_workspace`

Turning the output off **before** withdrawing the target is load-bearing. The
reverse order leaves the output present with the filter inert; Steam recomputes
in that window, caches the union of both monitors (6400x1440), and sizes the
*next* stream to it. This is the single most easily reintroduced bug in the
system.

### 4. The SDL filter

An `LD_PRELOAD` shim, ~370 lines of C, hooking exactly two symbols:
`SDL_GetDisplays` and `SDL_GetDisplayBounds`. It presents one display, sized to
the published stream target, placed at the origin.

Three properties that are not obvious:

- **It terminates the array, not just the count.** Steam calls
  `SDL_GetDisplays(NULL)` — the count argument is genuinely unused (`push 0`
  immediately before the call). Anything that only shortens the count has no
  effect on the routine that decides the geometry.
- **It is scoped to the Steam client** by `/proc/self/exe` basename (`steam`,
  `steamwebhelper`). Games, Proton and gamescope launched from Steam inherit the
  `LD_PRELOAD` but the filter is inert in them.
- **It is inert unless armed.** No `STEAM_STREAM_SIZE` and no readable
  `STEAM_STREAM_TARGET` file means every hook falls straight through to the
  real SDL.

**Nothing in it is compositor-specific.** `STEAM_STREAM_SIZE=1280x800` before
starting Steam is enough on its own, on any Wayland compositor or none. The
watcher is the niri-specific half; the filter is reusable as-is.

The multiarch layout in `pkgs/default.nix` matters: Steam runs both 32- and
64-bit processes, and a single-ABI `LD_PRELOAD` makes every process of the
other ABI print `wrong ELF class` before ignoring it. The path uses `$LIB` so
the loader picks the right one per process.

### 5. Host wiring

`flake-modules/hosts/ali-desktop/default.nix` sets, in Steam's environment:

- `LD_PRELOAD` — the multiarch filter (and `extest`, repeated because the Steam
  module's own `LD_PRELOAD` would otherwise be overwritten)
- `STEAM_STREAM_TARGET` — the path the watcher publishes to and the filter reads

## How the couplings actually work

```
        Steam logs ─────────────┐
                                ▼
  niri event-stream ───────► stream-mode ──► niri msg  (output mode/enable,
                                │             workspace move, column width,
                                │             focus)
                                │
                                └──► target file ──► SDL filter ──► Steam's
                                     (WIDTHxHEIGHT)   (in Steam)     desktop
                                                                     geometry
```

The target file is the entire interface between the two halves. The watcher
never talks to the filter and the filter never talks to niri; a file containing
nine bytes is the whole contract. That is deliberate — it is what lets the
filter be useful without the watcher, and lets the watcher be replaced by
anything that can write a file.

## What each side may assume

| | May assume |
|---|---|
| Filter | Only that the target file, if present and readable, holds `WIDTHxHEIGHT`. Nothing about niri, workspaces, or who wrote it. |
| Watcher | Only that Steam writes its logs and that niri answers IPC. Nothing about whether the filter is loaded — a Steam without it still streams, just at the wrong geometry. |

Each degrades independently, which is why diagnosing this is tractable at all:
a wrong capture size implicates the filter, a wrong window placement implicates
the watcher, and the two symptoms do not overlap.

## Covering the output

`set_window_fullscreen(window_id, True)` — genuine fullscreen, not a maximised
column. This matters because **a column is laid out inside the working area**,
so anything reserving an exclusive zone on the streamed output takes its space.
The desktop bar (noctalia here) renders on every output by default and reserved
34px on the virtual one, so a client asking for 1280x800 received 1280x766 of
game with a status bar above it. Fullscreen ignores struts, gaps and borders,
and needs no cooperation from whatever else runs on the desktop.

Getting there took two false starts, both worth not repeating:

- **A maximised column** (`set-column-width "100%"`) was chosen because it is
  idempotent and needs no state. It gets the width right and can never get the
  height right against an exclusive zone.
- **`fullscreen-window`** is upstream niri's only option and is a *toggle*,
  with no fullscreen state exposed to read first (niri-wm/niri#2836, #338).
  Inferring the state from geometry once turned an already-fullscreen game back
  into a windowed one.

`patches/niri-virtual-outputs.patch` therefore adds `set-window-fullscreen`,
which says what the state should be. The layout layer already took a bool
(`Layout::set_fullscreen`); only the IPC surface was missing. Being idempotent,
it can be sent on every event reporting the wrong size without tracking what
was already done — the property the column-width workaround was picked for in
the first place, now with correct geometry.

The window is taken **back out** of fullscreen when the game workspace returns
to its own monitor, so a game outliving the stream does not keep it. The niri
window rule deliberately does not force fullscreen on games, because that
overrode gamescope's own borderless sizing; the stream borrows that state and
gives it back.

`warn_if_short_of_output` remains as the guard: it logs once per window when a
window still does not exactly equal the output.

### Telling a shortfall's causes apart

Worth knowing, because it cost a wrong theory: a window short of the output
looks the same whatever the cause. **Read the horizontal loss.** Gaps and
borders are symmetric, so they cost width as well as height; a layer-shell
exclusive zone costs height only. The streamed window lost 0 horizontally and
34 vertically, which ruled out gaps and borders before any code changed — and
pointed at the bar rather than at the window's sizing mode.

## What gets touched

Only the staged game, and — while a game is staged — anything else that arrives
on the streamed output, because a game with a splash screen replaces its window
after staging has happened and the replacement matches nothing by name.

Acting on whatever sat on the output regardless once resized a terminal that
drifted there ninety seconds *after* the game exited. A staged game's pid is
cleared on exit, and that is what separates the two cases. The distinction
matters more now than it did: the same mistake that produced an oddly wide
terminal would now produce a fullscreen one.

## Testing without fooling yourself

The traps here are unusually good at producing false passes. In short:

- **Two outputs must be present.** With DP-2 detached there is nothing to filter
  and every probe trivially passes. Use a synthetic second output, and remove it
  afterwards — a stray virtual output left behind once became the focused output
  and read as a hung machine.
- **Verify through the path Steam uses.** `steamui.so` has
  `DT_NEEDED libSDL3.so.0`, so its calls go through the PLT and `LD_PRELOAD`
  interposes them. A probe that `dlopen`s SDL and resolves with a handle-scoped
  `dlsym` bypasses the preload and reports "unfiltered" however well the filter
  works. `pkgs/steam-display-filter/sdl_probe.c` does it correctly.
- **Force a recompute in seconds** rather than reconnecting a Deck:
  `niri msg create-virtual-output --name trigger --width 1920 --height 1080
  --refresh-rate 60`, then remove it. Each create/remove makes Steam re-emit
  `Desktop state changed`.
- The watcher's own behaviour is covered by `tests/test_stream_mode.py`
  (117 tests), which runs against a temporary state directory.

`PENDING.md` carries the longer list, including the diagnostics that once cost
more than the fault they were diagnosing.
