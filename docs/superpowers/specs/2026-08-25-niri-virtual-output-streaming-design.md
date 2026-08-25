# Streaming to a niri virtual output — design

- Date: 2026-08-25
- Host: `ali-desktop` (niri 26.04, AMD RDNA4, single 5120x1440 ultrawide on DP-2)
- Clients: Steam Deck (1280x800) today, Steam Frame later
- Supersedes the capture approach in `2026-08-24-steam-streaming-design.md` §6a/§6h

## 1. Problem

Steam Remote Play captures a whole output. On a 5120x1440 ultrawide that means
a 1280x800 Steam Deck receives roughly 1280x360 of content inside an 800-line
frame, and the content is whatever happens to be on screen rather than the
game.

Every approach that keeps the physical monitor as the capture source has now
been tried and has failed for a structural reason (§2). What remains is to give
Steam a *different monitor* to capture: a virtual output sized to the client,
with the game on it, leaving the physical display untouched.

niri does not support virtual outputs today. This design adds that support and
builds the streaming behaviour on top of it.

## 2. What has been established

Findings from the 2026-08-24 session. These are evidence, not assumptions, and
they are why the earlier approaches were abandoned.

**Steam requests MONITOR sources only.** Steam's portal picker offers only the
physical monitor and has no tab selector. Another client (`tofi-drun`) on the
same portal, at the same time, gets a picker with `Window | Display` tabs. The
portal offers windows to clients that ask; Steam does not ask. [confirmed by
direct comparison of both dialogs]

**Consequence: no window-scoped source can reach Steam.** niri's dynamic cast
target (25.05+) works and is correctly wired — `set-dynamic-cast-window`
succeeds and the watcher targets the right window every time — but it is
offered under the picker's "Window" tab, which Steam never shows.

**The portal stack is not misconfigured.** niri owns
`org.gnome.Mutter.ScreenCast` on the session bus, so it is built with the
`xdp-gnome-screencast` Cargo feature and window enumeration works.
`xdg-desktop-portal-gnome` is the backend niri's own documentation recommends.
`xdg-desktop-portal-gtk` does not implement ScreenCast at all;
`xdg-desktop-portal-wlr` does but offers no window casting.

**Capture geometry is fixed at session start.** The PipeWire stream is
negotiated when streaming begins and does not follow a later output mode
change: Steam keeps reporting the original geometry, and the renegotiation
churn is visible to the client as flicker. Any mode selection must therefore
happen *before* a session starts.

**A narrowed output does not make a tiled game fill it.** A smaller desktop is
still a desktop.

**A separate headless gamescope session is the wrong trade.** It captures
correctly, but Steam is single-instance: while it holds Steam, desktop clicks
are forwarded into a session that cannot be seen, and stopping the unit kills
gamescope, which takes Steam down with it.

### Upstream state of virtual outputs

- niri has no virtual output support upstream. Discussion #3101 proposes
  `niri msg action create-virtual-output` plus a `virtual` output config
  keyword, with outputs held in `niri.virtual_outputs`. The author has "a
  minimal implementation working"; the maintainer is supportive on details
  (preferring a synthetic fixed refresh rate) but nothing is merged and no
  branch is linked.
- `QaidVoid/niri` branch `feat/virtual` carries a working implementation: 2
  commits, ~520 added lines across `src/backend/headless.rs`,
  `src/backend/tty.rs`, `src/backend/mod.rs`, `src/ipc/{client,server}.rs`,
  `src/cli.rs`, `src/main.rs`, `src/niri.rs`, `niri-ipc/src/lib.rs`, plus
  `docs/Virtual-Outputs.md`. Last commit 2026-05-02; 74 commits behind
  upstream. The author reports testing it with Moonlight/Sunshine and wayvnc.

### niri primitives available

| Need | Command | Note |
|---|---|---|
| Move a window to an output | `niri msg action move-window-to-monitor <OUTPUT> --id <ID>` | works by id |
| Fullscreen a window | `niri msg action fullscreen-window --id <ID>` | **toggle only** |
| Focus a window | `niri msg action focus-window --id <ID>` | |
| Enumerate windows | `niri msg --json windows` | gives `pid`, `layout.window_size`; **no fullscreen flag** |
| Enumerate outputs | `niri msg --json outputs` | gives `modes`, `current_mode`, `logical` |

Fullscreen state has to be inferred from whether a window fills its output's
logical size, because niri exposes no flag and offers only a toggle — a blind
toggle un-fullscreens a game that already is.

### Steam log signals

```
Adding window 4194306 (4) for process 2331545 and gameID 2854740
Removing process 2163386 for gameID 2854740
>>> Starting desktop stream
>>> Capture resolution set to 1280x800
>>> Stopped desktop stream
```

`remote_connections.txt` additionally logs
`Client <id> (<name>) connected via direct connection` **before** streaming
negotiates, which is the only hook available early enough to prepare an output.

## 3. Goals

- A streamed game reaches the client full-frame at the client's own resolution,
  with no letterboxing and nothing else in view.
- The physical ultrawide is never reconfigured. No mode changes, no flicker, no
  desktop reflow.
- No second Steam instance, and no interaction on the host — it must work when
  nobody is at the machine.
- Sunshine and the Quest/WiVRn path keep working.

## 4. Non-goals

- Upstreaming virtual output support to niri. Contributing the rebased patch is
  welcome if it goes well, but this design does not depend on it landing.
- Steam Frame specifics. The design is parameterised by client resolution, so a
  Frame is a configuration value once its resolution is known.
- Fixing Steam's monitor-only portal request. That is Steam's to fix.

## 5. Design

### 5a. Patch niri with virtual output support

Carry `feat/virtual` as a **patch file in this repo**, applied via an overlay to
`inputs.niri`, in the same style as the existing `bubblewrap-allow-caps.patch`.
No fork to maintain and no second flake input.

The patch must be rebased from its 2026-05-02 base onto the niri rev the flake
pins. It is small and confined to backend/IPC files, so a rebase is expected to
be mechanical, but it is the main ongoing cost of this design (§7).

Expose it as `modules.desktop.niriVirtualOutputs` (or equivalent) so the patch
can be switched off in one line if a rebase goes bad.

### 5b. Validate nested before adopting

**Do not put a patched compositor under the login session until it is proven.**
niri can run nested inside the running niri as a window. In that nested
instance:

1. Create a 1280x800 virtual output.
2. Confirm it appears in a portal picker's **Display** list — not Window.
3. Confirm capturing it yields a 1280x800 stream.

Step 2 is the load-bearing unknown in this whole design. If a niri virtual
output does not appear as a Display to a monitor-only client, the design fails
and nothing further should be built. Establish it nested, at zero risk to the
session.

### 5c. Virtual output lifecycle

Owned by the existing `stream-mode` service, extending what it already does.

- **On client connect** (`remote_connections.txt`), create a virtual output at
  the client's remembered resolution. Connect is the trigger because capture
  geometry is fixed at session start (§2), and creating an output is
  non-destructive — unlike the Steam restart that made connect unusable as a
  trigger for the headless design.
- **Learn the client's resolution** from the first `Capture resolution set to
  WxH` of a session, persisted per client id. The first ever session for a new
  client uses a configured default.
- **On game window** (`Adding window … for process <pid>`), place the game on
  the virtual output (§5d).
- **On game exit / stream stop**, move the window back to DP-2 and destroy the
  virtual output after a short idle delay, so a reconnect does not thrash it.

The virtual output must never outlive a session: a stray extra output changes
where new windows open.

### 5d. Placing the game — two paths

**Launch-time, for gamescope titles.** gamescope's render resolution is fixed
by `-W/-H` at launch, so moving its window to a smaller output scales rather
than re-renders. `steam-command-runner` already intercepts `gamescope` in every
Steam launch chain from `~/.local/bin/gamescope`, which is exactly the right
place: when a stream is active it rewrites `-W/-H` to the client resolution and
adds `--prefer-output <virtual>`, so the game opens on the virtual output at
native resolution and never moves.

**Runtime move, for everything else.** Native and Proton titles without
gamescope respond to a configure event, so
`move-window-to-monitor <virtual> --id <N>` plus fullscreen is sufficient. This
path also covers a game already running when streaming starts.

### 5e. Fallback

When virtual outputs are unavailable — patch disabled, rebase failed, or the
§5b validation never passed — fall back to the behaviour built on 2026-08-24:
fullscreen the game on DP-2 so the stream at least shows the game rather than
the desktop, accepting the letterboxing. This is the current committed state
and stays the default until §5b passes.

## 6. Verification

1. §5b nested validation. Blocking; nothing proceeds without it.
2. Virtual output created and destroyed cleanly across connect/disconnect, with
   no leftover outputs (`niri msg --json outputs`).
3. A gamescope title opens on the virtual output at client resolution, with
   `niri msg --json windows` confirming the window size matches.
4. A non-gamescope title moves and fullscreens correctly.
5. The Deck receives a full-frame game with no letterboxing.
6. DP-2 is untouched throughout — mode and window layout unchanged.
7. Sunshine's existing entries still work; the Quest still connects via WiVRn.

Record each in the probe log alongside the 2026-08-24 rows.

## 7. Risks

**Patching the compositor that runs the session.** A failed rebase after a
flake update means no desktop. Mitigated by: the patch being small and
confined; a one-line off switch; NixOS generations for rollback; and never
adopting an unvalidated build (§5b). This is a standing maintenance cost and
the main reason to consider upstreaming.

**The payoff is unproven.** §5b exists precisely because "a virtual output will
appear as a Display" is an assumption. It is a reasonable one — virtual outputs
are advertised through the same Mutter ScreenCast path as physical ones — but
reasoning of exactly this shape was wrong twice on 2026-08-24.

**The fork is stale.** 74 commits behind, untouched since 2026-05-02, and
unreviewed by niri's maintainer. It is a starting point, not a dependency.

**Steam's own fragility is unrelated but will interfere with testing.** Two
traps are documented and will recur: a stale `~/.steam/steam.pid` after any
crash makes every subsequent start exit silently, and a `compatdata` prefix
whose recorded Proton version does not match the runner fails every launch with
`could not load kernel32.dll, status c0000020`. Neither is caused by streaming;
both will masquerade as streaming faults during a test session. Clearing the
stale pid belongs in the `steam` shim as separate work.

## 8. Open questions

- Does a niri virtual output appear to a monitor-only portal client as a
  Display? (§5b — blocking)
- Does the rebase onto current niri apply cleanly, and does the result pass
  `niri validate` and run nested?
- Does gamescope's `--prefer-output` accept a virtual output name, and does
  scopebuddy's existing `-O DP-2` need overriding rather than appending?
- What refresh rate should a virtual output advertise? #3101's maintainer
  comment favours a synthetic fixed rate; the client's own rate is the obvious
  choice.
- Does Steam's "Remember this selection" pin capture to a *specific* output, so
  that a virtual output appearing later is not selected automatically? If so,
  the remembered selection may have to be cleared once, or the virtual output
  given a stable name.

## 9. Order of work

1. Rebase `feat/virtual` onto the pinned niri rev; add as a patch + overlay with
   an off switch.
2. Build patched niri. Do not switch the session.
3. §5b nested validation. **Stop here if it fails.**
4. Adopt patched niri for the session; confirm the desktop is unaffected.
5. Virtual output lifecycle in `stream-mode` (§5c), including client-resolution
   learning.
6. Launch-time placement via the `steam-command-runner` shim (§5d).
7. Runtime move path for non-gamescope titles (§5d).
8. Full verification (§6); update the probe log.
9. Consider offering the rebased patch upstream to #3101.
