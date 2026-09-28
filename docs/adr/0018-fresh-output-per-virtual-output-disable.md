# 0018. Build a fresh output each time the `steam` virtual output is turned off

- Status: Accepted
- Date: 2026-09-28

## Context

From about 2026-09-20, apps on ali-desktop crashed with SIGSEGV several times a
day: Zen, kwalletd6, ksecretd, drkonqi, xdg-desktop-portal-gtk, OBS, Discord.
The stacks had nothing in common. There were no machine-check or EDAC errors.

Most crashes landed within 6 s of niri adding the `steam` virtual output, which
stream-mode turns on and off for every Remote Play connect (about 125 times in
8 days). In that window: 21 of 25 kwalletd6 crashes, 17 of 28 ksecretd, 65 of
104 drkonqi and 11 of 33 Zen. A random 6 s window would hit one about 0.1% of
the time.

The faulting pointer was always the output's size packed as two int32s:
`0x32000000500` is 1280x800 and `0x438000006c0` is 1728x1080. That value turned
up in a GTK app (inside glibc malloc) and in Qt apps (walking a `QObject`
connection list). The Qt apps load GDK too, because the session sets
`QT_QPA_PLATFORMTHEME=gtk3`.

A `WAYLAND_DEBUG` trace of a GTK 3 probe during `niri msg output steam on`/`off`
showed the cause. Each time the output came back on, niri sent
`zxdg_output_v1.logical_size(1728, 1080)` to every xdg_output object from the
earlier cycles (#31, #33, #35…), not just the new one:

- smithay keeps an `Output`'s xdg_output resources on the `Output` itself, not
  on its global. The virtual-output patch re-added the same `Output` under a new
  global on every enable, so the old resources kept receiving events.
- GTK 3.24.52's `gdk_wayland_monitor_finalize` destroys the `wl_output` but
  leaks the `zxdg_output_v1` proxy, whose user data still points at the freed
  monitor. `xdg_output_handle_logical_size` then writes the width and height
  into freed memory. GTK fixed the leak in GNOME/gtk!10014 (merged to
  `gtk-3-24` on 2026-06-27), but no GTK release contains it yet and nixpkgs
  doesn't carry it.

Toggling `steam` nine times by hand crashed Zen during the run.

## Decision

In the niri fork (`rebase-feat-virtual`, regenerated into
`patches/niri-virtual-outputs.patch`), turning a virtual output off swaps in a
new smithay `Output` with the same name, physical properties and current mode.
This matches what upstream niri already does when a monitor reconnects.

The swap happens at turn-off, not turn-on. On a connect, niri resizes the
output before it re-enables it. If the old `Output` were still held at that
point, the resize alone would send `logical_size` to the leftover objects.

A resize also drops the previous mode. Before this, `steam` advertised 14
accumulated modes, one for every client panel size it had ever served.

## Alternatives rejected

- **Patch Qt.** Qt was not at fault; it crashed on memory GDK had corrupted.
- **Backport GNOME/gtk!10014 into `gtk3` with an overlay.** It fixes only GTK,
  and it forces an uncached rebuild of everything that depends on gtk3. Take it
  when it arrives in a nixpkgs release instead.
- **Keep `steam` on permanently.** New windows would keep opening on the
  invisible output (commit 2b5c2745).

## Consequences

Clients no longer receive events for outputs they have released, however often
`steam` is toggled. Any state niri keeps in the `Output`'s user data is lost on
re-enable, apart from the output name. Nothing outside the output name is
stored there today.

## Evidence

- Core dumps: `coredumpctl info` on kwalletd6 PID 730922 and Zen PID 1429094.
  The faulting registers hold the size values above.
- Probe trace: `zxdg_output_v1#31.logical_size(1728, 1080)` arriving on every
  re-enable after `wl_registry.global_remove(131)`.

## Revisit when

- nixpkgs ships a GTK 3 release containing GNOME/gtk!10014. This fix stays,
  because the old events are wrong for any client.
- The virtual-output patch is upstreamed, so this fix goes with it.
