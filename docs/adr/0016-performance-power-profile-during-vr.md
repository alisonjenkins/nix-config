# 0016. Hold the performance power profile for a VR session's lifetime, event-driven

- Status: Accepted, causation unconfirmed
- Date: 2026-09-22 (rewritten 2026-09-25 after the cited evidence could not
  be reproduced; reworked 2026-09-26 to fix a conflict with 0005)

## Context

Beat Saber, streamed from `ali-desktop` to a Quest 2 over Steam Link, had
choppy, stuttering audio in the headset. Commit `13412587`
(`fix(ali-desktop): bump power profile to performance during VR sessions`)
attributed this to `power-profiles-daemon`'s `balanced` profile letting
`amd_pstate` clock the CPU down between bursts, citing repeated
`CAudioJitterBuffer` fade-out/fade-in entries in SteamVR's
`driver_vrlink.txt` as evidence, timed to the audible crackle. It shipped
as a `systemd.timer` polling `pgrep vrserver` every 5s and calling
`powerprofilesctl set performance`/`balanced`.

That citation does not hold up. Checked directly against the logs on
`ali-desktop`: `driver_vrlink.txt` and its rotated predecessor contain zero
lines matching `jitter` or `audio` — every line is `SVL*`-prefixed
SteamVR-Link transport chatter, a different subsystem from Steam's
streaming stack, whose own host log is `streaming_log.txt`. That file
also has no `CAudioJitterBuffer` hits for the session in question (rotated
out; the surviving file starts 2026-09-24). The line cannot currently be
confirmed to have existed as described.

Separately, even a genuine jitter-buffer fade would not, by itself, point
at the CPU frequency governor specifically: PipeWire's audio thread runs
`SCHED_FIFO` under RTKit (see [audio-rt-scheduling] in memory, not yet an
ADR), so it is not clock-starved the way a `SCHED_OTHER` thread would be.
A fade of that kind is equally consistent with:

- Network-side jitter to the Quest 2 or through a Steam Datagram Relay hop
  (`streaming_log.txt` shows `Connected SDR->lhr->lhr` relay lines and
  `thread starvation` warnings independent of CPU governor).
- A PipeWire graph rate switch (`clock.allowed-rates = [44100, 48000]`):
  a client that opens at 44.1kHz forces the whole graph, including the
  desktop's 8-node SOFA binaural filter-chain
  ([0015](0015-positioned-sink-for-stream-audio.md)), to reconfigure
  mid-session.
- Quantum renegotiation when Steam's capture joins the graph (dynamic
  quantum 256–4096; partitioned convolution costs much more per sample at
  256).
- General CPU contention between the game, the encoder and the audio
  pipeline, independent of which governor is active.

The original poll-and-set timer also had its own, independent problems,
found on review:

- It **conflicts with [0005](0005-stream-mode-owns-stream-state.md)**, an
  Accepted ADR in this repo stating the streaming stack's watcher "reacts
  to events and never polls," specifically to avoid the failure modes a
  poll loop invites.
- `powerprofilesctl set` is global, not a hold: it overwrites any other
  reason the profile might be `balanced` or `performance` (a manual
  change, a desktop-environment power applet) on every poll, and would
  leave the box pinned at `performance` forever if the timer's own service
  died mid-VR-session, since nothing else would ever set it back.

## Decision

Rework the mechanism to be event-driven and to use a cooperative hold
instead of a global `set`, without asserting it is a confirmed fix for the
reported stutter (see Evidence): `systemd.services.steamvr-power-profile`
(`flake-modules/hosts/ali-desktop/default.nix`) runs a long-lived loop
that:

1. Blocks on `inotifywait -e create /dev/shm` until vrserver's own IPC
   shared-memory segment, `/dev/shm/u*-ValveIPCSharedObj-SteamVR`, appears
   (already relied on by `steamvr-setcap`'s cleanup logic in the same
   file). No polling interval — the loop only wakes on that specific
   filesystem event.
2. Once it exists, runs `powerprofilesctl launch -p performance -r
   "vrserver holding $shm" -- inotifywait -e delete_self "$shm"`.
   `launch` opens a D-Bus connection to `power-profiles-daemon`, calls
   `HoldProfile`, and keeps that connection open for its child's
   lifetime — here, `inotifywait` blocking on the same segment's deletion,
   i.e. for exactly as long as `vrserver` runs.
3. Loops back to step 1 for the next session.

Because the hold is released automatically when `powerprofilesctl
launch`'s child exits — cleanly, killed, or because the whole service
was killed — a crash can no longer leave the profile pinned. Because a
hold layers on top of whatever profile is already active rather than
overwriting it, this also now composes with `ppd-set-balanced` (same
file), which sets the boot-time default: releasing the hold restores
`balanced` rather than leaving whatever `set` last wrote.

## Alternatives rejected

- **Pin `performance` permanently.** Rejected: unwanted power draw on a
  24/7 machine outside VR sessions.
- **Keep polling `pgrep vrserver` on a timer.** Rejected: this is what
  conflicted with 0005; the SHM segment gives an actual event to block on
  instead.
- **A `systemd.path` unit watching the SHM path.** `PathExists`/
  `PathExistsGlob` triggers a `start`, which is a no-op on an
  already-active unit and does not naturally express "hold until this
  path is removed" — the existing `steamvr-setcap` timer in this file
  hit exactly this shape of problem with a self-retriggering path unit.
  A single service blocking on `inotifywait` for both the create and the
  matching delete event covers the same lifetime without that.
- **A raw D-Bus `HoldProfile`/`ReleaseProfile` script (e.g. via
  `busctl call`).** Each `busctl call` opens and closes its own
  connection, so a `HoldProfile` call followed later by a separate
  `ReleaseProfile` call has no held connection in between — a crash
  between the two would leak the hold exactly like the plain `set` did.
  `powerprofilesctl launch` already keeps one connection open around a
  child process for this reason; reimplementing it was unnecessary.

## Consequences

- VR sessions get full CPU boost clocks for their entire duration, which
  costs power and fan noise the balanced profile was chosen to avoid
  outside VR — unchanged from the original mechanism.
- Still uncoordinated with the other scheduling layers on ali-desktop
  (`scx_lavd --performance` via `services.scx`, ananicy-cpp with CachyOS
  rules) — this ADR only fixes the 0005 conflict and the crash-safety
  problem, not that broader lack of coordination.
- A session that starts and finishes between one `inotifywait -e create`
  wakeup and the loop re-arming (i.e. a vrserver that appears and
  disappears faster than the loop can react) would miss the hold
  entirely. Not expected in practice: vrserver's own startup and a Beat
  Saber session both run for at least seconds.
- `RestartSec=2s`/`Restart=on-failure` recovers the outer loop if
  `inotifywait` itself ever exits with an error (e.g. `/dev/shm` briefly
  unreadable); the inner `|| true` on the `launch` line prevents a normal
  session end from being treated as a service failure.

## Evidence

- Commit `13412587`'s message cites `driver_vrlink.txt` `CAudioJitterBuffer`
  fade-out/fade-in lines. **Not reproducible**: neither the current
  `driver_vrlink.txt`/`.previous.txt` nor `streaming_log.txt` on
  `ali-desktop` contain a matching line as of 2026-09-25. The originally
  cited session's log has since rotated out.
- Live state confirmed 2026-09-25: PPD profile `balanced`, governor
  `powersave`, EPP `balance_performance` — the mechanism this ADR's fix
  targets is real and currently in that state outside VR sessions, only
  the causal link to the reported audio stutter is unconfirmed.
- The streaming host leg to the Quest 2 is wired (`SO_BINDTODEVICE` on
  `enp16s0`); only the AP-to-Quest hop is wireless, narrowing where
  network jitter could enter.
- `inotify-tools`, `powerprofilesctl launch -p/-r`, and the SHM glob
  pattern verified against nixpkgs and `powerprofilesctl --help` on
  2026-09-26; script extracted and run through `shellcheck` clean. Not
  yet run against a live `vrserver` session — the user could not
  reproduce during this session.

## Revisit when

- The stutter is reproduced again with the hold confirmed active
  (`powerprofilesctl get` mid-session, or `powerprofilesctl list-holds`
  showing the `vrserver holding ...` reason) — if it still stutters, this
  mechanism is not the fix and should be superseded or reverted.
- The next reproduction, capture the actual discriminating evidence
  instead of relying on a governor correlation: `pw-top -b` during the
  session for host-side xruns, and `streaming_log.txt`'s per-minute
  `Audio source [System Pulse]: mixed=, adjustment=, drop_before=,
  drop_after=` counters. Zero host xruns and `drop_before/after=0` while
  client-side starvation lines still appear rules out the CPU profile
  entirely. Fade periodicity is also informative: regular fades suggest
  clock/resampler drift (`clock.force-rate`), irregular bursts suggest
  load.
- This ADR is cited elsewhere as settled causation for the original
  stutter — it is not; treat it as an untested mitigation until the above
  is run.
